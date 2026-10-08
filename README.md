# AXI-Stream Packet Receiver

A small custom IP core for experimenting with the Vivado IP flow: an AXI4-Stream packet receiver and a FIFO, packaged as a reusable IP with standard AXI interfaces.

The core buffers an AXI4-Stream through a FIFO and counts the packets passing through it. The counters are read and controlled over AXI4-Lite.

## What it does

```
                 ┌──────────────────────────────────────┐
  s_axis  ─────► │  FIFO with bypass (1024 entries)     │ ─────►  m_axis
  (tdata, tkeep, │                                      │   (tdata, tkeep,
   tlast)        └──────────────────────────────────────┘    tlast)
                        │ counts beats and packets
                        ▼
                 ┌──────────────────────────────────────┐
  s_axil  ◄────► │  Control and status registers        │
                 └──────────────────────────────────────┘
```

- **Stream path.** Data arriving on `s_axis` is forwarded to `m_axis` through a FIFO, with `tkeep` and `tlast` carried alongside `tdata`.
- **Packet statistics.** When counting is enabled, the core counts every beat accepted on `s_axis` and uses `tlast` to mark the end of a packet.
- **Register access.** An AXI4-Lite slave exposes one control register and three read-only counters.

## Register map

All registers are 32 bits wide.

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x0` | `CONTROL` | read/write | Bit 0: enable counting. Bit 1: write 1 to clear all counters (self-clearing, reads as 0). |
| `0x4` | `BURSTS_COUNT` | read-only | Number of complete packets seen since the last clear. |
| `0x8` | `CURRENT_BURST_BEATS` | read-only | Beats received so far in the packet currently in progress. |
| `0xC` | `LAST_BURST_BEATS` | read-only | Number of beats in the most recently completed packet. |

- A write to any offset other than `0x0`, or a read from an unmapped offset, returns `SLVERR`.
- `WSTRB` is ignored; writes always update the whole register.
- The write address and write data channels are accepted independently and in either order. The response is sent once both have arrived.

## The FIFO

`rtl/fifo.sv` is a synchronous FIFO with a valid/ready interface on both sides and two shortcuts that avoid wasted cycles:

- **Bypass when empty.** If the FIFO is empty, incoming data is presented on the output in the same cycle. If the downstream side accepts it immediately, it is never written to memory.
- **Accept when full.** If the FIFO is full but a word is being read in the same cycle, a new word is accepted.

Full and empty are distinguished with read and write pointers one bit wider than the address, so `DEPTH` must be a power of two.

These shortcuts create combinational paths from input to output (`valid` and data) and from `data_out_ready` back to `data_in_ready`.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 32 | Width of `tdata` and of the AXI4-Lite data bus. |
| `KEEP_WIDTH` | `DATA_WIDTH/8` | Width of `tkeep` and `WSTRB`. |
| `ADDR_WIDTH` | 4 | Width of the AXI4-Lite address. |

The FIFO depth is fixed at 1024 entries inside `axis_packet_receiver.sv`.

Clock and reset are `aclk` and `arst_n` (active-low, asynchronous).

## Repository layout

| Path | Contents |
|---|---|
| `rtl/` | SystemVerilog source: the top-level `axis_packet_receiver` and the `fifo`. |
| `ip_repo/` | The core packaged as a Vivado IP (`component.xml`, customisation GUI, and a copy of the sources). |
| `vivado/` | Tcl script that recreates the Vivado project. |

## Using it

Developed with Vivado 2023.2, targeting a Zynq-7020 (`xc7z020clg400-1`) on an Avnet MicroZed board.

**Add the IP to an existing project**

1. In Vivado, open *Settings → IP → Repository*.
2. Add the `ip_repo/` directory of this repository.
3. `axis_packet_receiver` then appears in the IP catalog and can be dropped into a block design.

**Recreate the original project**

The project script uses paths relative to the directory that *contains* this repository, so run it from there:

```bash
cd <directory containing axis_packet_receiver/>
vivado -mode batch -source axis_packet_receiver/vivado/axis_packet_receiver.tcl
```
