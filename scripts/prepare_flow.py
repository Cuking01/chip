#!/usr/bin/env python3
"""Resolve OpenLane's source settings for the SystemVerilog lowering step."""

import argparse
import json
from pathlib import Path

from prepare_sv import stage_sources

def flatten(value):
    if value is None:
        return []
    if isinstance(value, list):
        return [item for child in value for item in flatten(child)]
    return [value]


def main():
    # This helper runs inside the existing OpenLane image so path expressions
    # and PDK-specific configuration sections use its own JSON preprocessor.
    from openlane.config.preprocessor import preprocess_dict

    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    parser.add_argument("filelist", type=Path)
    args = parser.parse_args()
    raw = json.loads(args.config.read_text())
    pdk = raw.get("PDK", "sky130A")
    scl = raw.get("STD_CELL_LIBRARY", "sky130_fd_sc_hd")
    config = preprocess_dict(
        raw,
        str(args.config.parent),
        pdk=pdk,
        pdkpath=f"/workspace/pdks/{pdk}",
        scl=scl,
        readable_paths=["/workspace"],
    )
    sources = flatten(config.get("VERILOG_FILES"))
    if not sources:
        raise ValueError("VERILOG_FILES must contain at least one source file")
    options = ["--top", config["DESIGN_NAME"], "-D", "SYNTHESIS"]
    sources, includes = stage_sources(
        sources, args.filelist.parent / "preprocessed" / "flow",
        flatten(config.get("VERILOG_INCLUDE_DIRS")),
    )
    for directory in includes:
        options.extend(["-I", directory])
    for definition in flatten(config.get("VERILOG_DEFINES")):
        options.extend(["-D", definition])
    parameters = config.get("SYNTH_PARAMETERS")
    if isinstance(parameters, dict):
        parameters = [f"{key}={value}" for key, value in parameters.items()]
    for parameter in flatten(parameters):
        options.extend(["-G", parameter])
    args.filelist.write_text(
        "\n".join(json.dumps(str(item)) for item in options + sources) + "\n"
    )


if __name__ == "__main__":
    main()
