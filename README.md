![CI](https://github.com/pulp-platform/snitch_cluster/actions/workflows/ci.yml/badge.svg)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# RISCV core Cluster

This repository hosts the hardware and software for a RISCV core cluster. It is based on the work of the PULP project, a joint effort between ETH Zurich and the University of Bologna.
## License

Snitch is being made available under permissive open source licenses.

The following files are released under Apache License 2.0 (`Apache-2.0`) see `LICENSE`:

- `sw/`
- `util/`

The following files are released under Solderpad v0.51 (`SHL-0.51`) see `hw/LICENSE`:

- `hw/`

The `sw/deps` directory references submodules that come with their own
licenses. See the respective folder for the licenses used.

- `sw/deps/`

## Publications


If you use the Snitch cluster or its extensions in your work, you can cite us:

<details>
<summary><b>Snitch: A tiny Pseudo Dual-Issue Processor for Area and Energy Efficient Execution of Floating-Point Intensive Workloads</b></summary>
<p>

```
@article{zaruba2020snitch,
  title={Snitch: A tiny Pseudo Dual-Issue Processor for Area and Energy Efficient Execution of Floating-Point Intensive Workloads},
  author={Zaruba, Florian and Schuiki, Fabian and Hoefler, Torsten and Benini, Luca},
  journal={IEEE Transactions on Computers},
  year={2020},
  publisher={IEEE}
}
```

</p>
</details>

<details>
<summary><b>Stream semantic registers: A lightweight risc-v isa extension achieving full compute utilization in single-issue cores</b></summary>
<p>

```
@article{schuiki2020stream,
  title={Stream semantic registers: A lightweight risc-v isa extension achieving full compute utilization in single-issue cores},
  author={Schuiki, Fabian and Zaruba, Florian and Hoefler, Torsten and Benini, Luca},
  journal={IEEE Transactions on Computers},
  volume={70},
  number={2},
  pages={212--227},
  year={2020},
  publisher={IEEE}
}
```

</p>
</details>

<details>
<summary><b>Sparse Stream Semantic Registers: A Lightweight ISA Extension Accelerating General Sparse Linear Algebra</b></summary>
<p>

```
@article{scheffler2023sparsessr,
  author={Scheffler, Paul and Zaruba, Florian and Schuiki, Fabian and Hoefler, Torsten and Benini, Luca},
  journal={IEEE Transactions on Parallel and Distributed Systems},
  title={Sparse Stream Semantic Registers: A Lightweight ISA Extension Accelerating General Sparse Linear Algebra},
  year={2023},
  volume={34},
  number={12},
  pages={3147-3161},
  doi={10.1109/TPDS.2023.3322029}
}
```

</p>
</details>

<details>
<summary><b>A High-performance, Energy-efficient Modular DMA Engine Architecture</b></summary>
<p>

```
@ARTICLE{benz2023idma,
  author={Benz, Thomas and Rogenmoser, Michael and Scheffler, Paul and Riedel, Samuel and Ottaviano, Alessandro and Kurth, Andreas and Hoefler, Torsten and Benini, Luca},
  journal={IEEE Transactions on Computers},
  title={A High-performance, Energy-efficient Modular DMA Engine Architecture},
  year={2023},
  volume={},
  number={},
  pages={1-14},
  doi={10.1109/TC.2023.3329930}}
```

</p>
</details>

<details>
<summary><b>MiniFloat-NN and ExSdotp: An ISA Extension and a Modular Open Hardware Unit for Low-Precision Training on RISC-V Cores</b></summary>
<p>

```
@inproceedings{bertaccini2022minifloat,
  author={Bertaccini, Luca and Paulin, Gianna and Fischer, Tim and Mach, Stefan and Benini, Luca},
  booktitle={2022 IEEE 29th Symposium on Computer Arithmetic (ARITH)},
  title={MiniFloat-NN and ExSdotp: An ISA Extension and a Modular Open Hardware Unit for Low-Precision Training on RISC-V Cores},
  year={2022},
  volume={},
  number={},
  pages={1-8}
}
```

</p>
</details>

<details>
<summary><b>Soft Tiles: Capturing Physical Implementation Flexibility for Tightly-Coupled Parallel Processing Clusters</b></summary>
<p>

```
@inproceedings{paulin2022softtiles,
  author={Paulin, Gianna and Cavalcante, Matheus and Scheffler, Paul and Bertaccini, Luca and Zhang, Yichao and Gürkaynak, Frank and Benini, Luca},
  booktitle={2022 IEEE Computer Society Annual Symposium on VLSI (ISVLSI)},
  title={Soft Tiles: Capturing Physical Implementation Flexibility for Tightly-Coupled Parallel Processing Clusters},
  year={2022},
  volume={},
  number={},
  pages={44-49},
  doi={10.1109/ISVLSI54635.2022.00021}
}
```

</p>
</details>

<details>
<summary><b>SARIS: Accelerating Stencil Computations on Energy-Efficient RISC-V Compute Clusters with Indirect Stream Registers</b></summary>
<p>

```
@misc{scheffler2024saris,
      title={SARIS: Accelerating Stencil Computations on Energy-Efficient
             RISC-V Compute Clusters with Indirect Stream Registers},
      author={Paul Scheffler and Luca Colagrande and Luca Benini},
      year={2024},
      eprint={2404.05303},
      archivePrefix={arXiv},
      primaryClass={cs.MS}
}
```

</p>
</details>
