#!/usr/bin/env python3
# Copyright 2024 Politecnico di Milano.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
#
# Description: generates the source filelist of a top module by following module, interface,
#              package and VHDL entity references from the top file. Files are emitted in
#              dependency order (definitions before users), paths relative to the repo root.
#              Output format (understood by create_project.tcl and xrun -f):
#                +incdir+<dir>       include directories
#                // global includes  files defining macros used by all the following files
#                <file>
#                // sources          rtl sources in compile order
#                <file>
#              Paths are relative to the repo root, except the build outputs of the run (bootrom,
#              VeeR snapshot, riscv-mini Tile, VexRiscv, VexiiRiscv): they are emitted as given, use absolute paths.
# Usage: gen_filelist.py <core> --bootrom <bootrom_<core>.sv> [--veer-snapshot <dir>]
#                        [--mini-rtl <Tile.sv>] [--vex-rtl <VexRiscvU55.v>]
#                        [--vex2-rtl <VexiiRiscvU55.v>] > <core>.f
# Author: Andrea Motta

import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# search roots shared by all the cores
COMMON_ROOTS = ['hw']
# never pick files from these paths (testbenches, duplicates, simulation only code)
EXCLUDE = ['Cores-VeeR-EL2/testbench', 'Cores-VeeR-EL2/verification', 'Cores-VeeR-EL2/tools',
           'Cores-VeeR-EL2/third_party', 'Cores-VeeR-EL2/configs', 'Cores-VeeR-EL2/docs',
           'Cores-VeeR-EL2/design/lib/mem_lib.sv',
           # VexRiscv sources are SpinalHDL: the core is generated in the build directory
           'cores/vex/VexRiscv/', 'cores/vex2/VexiiRiscv/',
           '/test/', '/tb/', '/tb_', 'tb_', '_tb.', 'deprecated', 'fpnew/src/fpu_div_sqrt_mvp',
           'dmi_bscane_tap', 'formal', 'axi_test', '_intf_test', 'axi_sim_mem', 'axi_dumper',
           '/util/', '/doc/', '_sim.sv', 'hw/cluster/tops/',
           # cva6 OpenPiton cache adapter (PITON_ARIANE only)
           'wt_l15_adapter']

CORES = {
    'snitch': {
        'top': 'hw/cluster/tops/u55_snitch_top.sv',
        'globals': ['hw/infra/axi_pulp/include/axi/axi_assign.svh'],
        'incdirs': [],
        'extra': ['{bootrom}'],
    },
    'cva6': {
        'top': 'hw/cluster/tops/u55_cva6_top.sv',
        'globals': ['hw/infra/axi_pulp/include/axi/axi_assign.svh'],
        'incdirs': [],
        'extra': ['{bootrom}'],
    },
    'veer': {
        'top': 'hw/cluster/tops/u55_VeeR_top.sv',
        'globals': ['{veer_snapshot}/common_defines.vh',
                    'hw/cores/veer/Cores-VeeR-EL2/design/lib/el2_assert.sv',
                    'hw/infra/axi_pulp/include/axi/axi_assign.svh'],
        # el2_param.vh is included inside module parameter lists: include dir only
        'incdirs': ['{veer_snapshot}', 'hw/cores/veer/Cores-VeeR-EL2/design/include'],
        'extra': ['{bootrom}'],
    },
    'mini': {
        'top': 'hw/cluster/tops/u55_mini_top.sv',
        'globals': ['hw/infra/axi_pulp/include/axi/axi_assign.svh'],
        'incdirs': [],
        # riscv-mini Tile, generated from chisel in the build directory
        'extra': ['{mini_rtl}', '{bootrom}'],
    },
    'vex': {
        'top': 'hw/cluster/tops/u55_vex_top.sv',
        'globals': ['hw/infra/axi_pulp/include/axi/axi_assign.svh'],
        'incdirs': [],
        # VexRiscvU55, generated from SpinalHDL in the build directory
        'extra': ['{vex_rtl}', '{bootrom}'],
    },
    'vex2': {
        'top': 'hw/cluster/tops/u55_vex2_top.sv',
        'globals': ['hw/infra/axi_pulp/include/axi/axi_assign.svh'],
        'incdirs': [],
        # VexiiRiscvU55, generated from SpinalHDL in the build directory
        'extra': ['{vex2_rtl}', '{bootrom}'],
    },
}
# modules provided by Vivado (IPs, block designs, unisim primitives)
EXTERNAL = {'hbm_interface', 'xlnx_clk_gen_cluster', 'xlnx_clk_gen_periph', 'ibuf', 'ibufds', 'bufg', 'ibufds_gte4', 'bufgce'}

SRC_EXT = ('.sv', '.v', '.vhd')
HDR_EXT = ('.svh', '.vh')

re_sv_def = re.compile(r'^\s*(?:module|macromodule|interface|package|program)\s+(?:automatic\s+|static\s+)?(\w+)', re.M)
re_vhd_def = re.compile(r'^\s*(?:entity|package)\s+(\w+)\s+is\b', re.M | re.I)
re_include = re.compile(r'`include\s+"([^"]+)"')
# references: instances "type [#(...)] name [...] (", packages "pkg::", interface ports "intf.modport name"
re_sv_refs = [re.compile(r'\b([A-Za-z_]\w*)\s*(?:#\s*\(|\s+[A-Za-z_]\w*\s*(?:\[[^\]]*\]\s*)*\()'),
              re.compile(r'\b([A-Za-z_]\w*)\s*::'),
              re.compile(r'\b([A-Za-z_]\w*)\.[A-Za-z_]\w*\s+[A-Za-z_]\w*\s*[,;)\[]')]
re_vhd_refs = [re.compile(r'\bentity\s+work\.(\w+)', re.I),
               re.compile(r'\bcomponent\s+(\w+)', re.I),
               re.compile(r'\buse\s+work\.(\w+)', re.I)]
re_sv_comment = re.compile(r'//[^\n]*|/\*.*?\*/', re.S)
re_vhd_comment = re.compile(r'--[^\n]*')


def excluded(path):
    return any(e in path for e in EXCLUDE)


def scan():
    sources, headers = [], []
    for root in COMMON_ROOTS:
        for dirpath, _, files in os.walk(os.path.join(REPO, root)):
            for f in files:
                p = os.path.relpath(os.path.join(dirpath, f), REPO)
                if excluded(p):
                    continue
                if f.endswith(SRC_EXT):
                    sources.append(p)
                elif f.endswith(HDR_EXT):
                    headers.append(p)
    return sorted(sources), sorted(headers)


def parse(path):
    with open(os.path.join(REPO, path), errors='replace') as fh:
        text = fh.read()
    vhdl = path.endswith('.vhd')
    text = re_vhd_comment.sub('', text) if vhdl else re_sv_comment.sub('', text)
    defs = [d.lower() for d in (re_vhd_def if vhdl else re_sv_def).findall(text)]
    incs = [] if vhdl else re_include.findall(text)
    idents = {i.lower() for r in (re_vhd_refs if vhdl else re_sv_refs) for i in r.findall(text)}
    return defs, incs, idents


def resolve_include(name, src, headers):
    # relative to the including file first, then anywhere in the repo (suffix match)
    local = os.path.normpath(os.path.join(os.path.dirname(src), name))
    if local in headers:
        return os.path.dirname(src)
    for h in headers:
        if h == name or h.endswith('/' + name):
            return h[:-len(name)].rstrip('/') or '.'
    return None


def main(core, bootrom, veer_snapshot, mini_rtl, vex_rtl, vex2_rtl):
    # build outputs of the run: bootrom, VeeR snapshot (veer.config), riscv-mini Tile (chisel),
    # VexRiscv and VexiiRiscv (SpinalHDL)
    fmt = {'bootrom': bootrom, 'veer_snapshot': veer_snapshot, 'mini_rtl': mini_rtl, 'vex_rtl': vex_rtl,
           'vex2_rtl': vex2_rtl}
    cfg = {k: ([x.format(**fmt) for x in v] if isinstance(v, list) else v.format(**fmt))
           for k, v in CORES[core].items()}
    if core == 'veer' and not os.path.isfile(os.path.join(REPO, veer_snapshot, 'common_defines.vh')):
        sys.exit(f'error: no VeeR snapshot in {veer_snapshot}')
    if core == 'mini' and not os.path.isfile(os.path.join(REPO, mini_rtl)):
        sys.exit(f'error: no riscv-mini rtl {mini_rtl}')
    if core == 'vex' and not os.path.isfile(os.path.join(REPO, vex_rtl)):
        sys.exit(f'error: no VexRiscv rtl {vex_rtl}')
    if core == 'vex2' and not os.path.isfile(os.path.join(REPO, vex2_rtl)):
        sys.exit(f'error: no VexiiRiscv rtl {vex2_rtl}')
    if not os.path.isfile(os.path.join(REPO, bootrom)):
        sys.exit(f'error: no bootrom {bootrom}')
    sources, headers = scan()
    # files in excluded paths that are needed anyway
    sources += [cfg['top']] + cfg.get('extra', [])
    info = {s: parse(s) for s in sources}
    owner = {}
    for s in sources:
        for d in info[s][0]:
            if d in owner and owner[d] != s:
                sys.exit(f'error: {d} defined in {owner[d]} and {s}, add one to EXCLUDE')
            owner[d] = s

    order, visited, incdirs, missing = [], set(), list(cfg['incdirs']), set()

    def visit(src):
        if src in visited:
            return
        visited.add(src)
        defs, incs, idents = info[src]
        idents = set(idents)
        # included headers (recursively): include dirs, and their references count as src ones
        pending, seen = [(inc, src) for inc in incs], set()
        while pending:
            inc, frm = pending.pop()
            d = resolve_include(inc, frm, headers)
            if d is None:
                missing.add(f'`include "{inc}" ({frm})')
                continue
            if d not in incdirs:
                incdirs.append(d)
            hdr = os.path.normpath(os.path.join(d, inc))
            if hdr in seen:
                continue
            seen.add(hdr)
            _, hincs, hidents = parse(hdr)
            idents |= hidents
            pending += [(i, hdr) for i in hincs]
        for ident in sorted(idents - set(defs)):
            if ident in owner:
                visit(owner[ident])
        order.append(src)

    visit(cfg['top'])
    for m in sorted(missing):
        print(f'warning: unresolved {m}', file=sys.stderr)

    print(f'// {core} sources, generated by tcl_scripts/filelists/gen_filelist.py {core}')
    for d in incdirs:
        print(f'+incdir+{d}')
    print('// global includes')
    for g in cfg['globals']:
        print(g)
    print('// sources')
    for s in order:
        if s not in cfg['globals']:
            print(s)


if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser(description='rtl filelist of a u55c top')
    ap.add_argument('core', choices=list(CORES))
    ap.add_argument('--bootrom', required=True,
                    help='bootrom_<core>.sv of the run (make -C bootrom_u55), absolute or relative to the repo')
    ap.add_argument('--veer-snapshot', default='build/veer/veer_snapshot',
                    help='VeeR-EL2 snapshot directory of the run, absolute or relative to the repo')
    ap.add_argument('--mini-rtl', default='build/mini/riscv_mini/Tile.sv',
                    help='riscv-mini Tile.sv of the run, absolute or relative to the repo')
    ap.add_argument('--vex-rtl', default='build/vex/vexriscv/VexRiscvU55.v',
                    help='VexRiscvU55.v of the run, absolute or relative to the repo')
    ap.add_argument('--vex2-rtl', default='build/vex2/vexiiriscv/VexiiRiscvU55.v',
                    help='VexiiRiscvU55.v of the run, absolute or relative to the repo')
    args = ap.parse_args()
    main(args.core, args.bootrom, args.veer_snapshot, args.mini_rtl, args.vex_rtl, args.vex2_rtl)
