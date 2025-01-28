# hotfix-kvadra-touchpad

This simple kernel module provides a hotfix for touchpad issues
KVADRA NAU LE14U and similar notebooks.

## The problem

On this notebook, after some idle time (10-30 minutes) touchpad stops
to work.

This notebook contains the Intel i5-1235U CPU, 4 Intel Corporation Alder Lake
PCH Serial IO I2C Controllers I2C controllers and SYNA3602 touchpad, connected
via I2C serial bus.

I2C controllers use interrupts 27, 31, 32 and 40, shared between the
`i2c_designware` and `idma64` modules, but only IRQ #27 seems to be really
active.

Both `/sys/devices/pci0000:00/0000:00:19.0/dma/dma3chan0/bytes_transferred`
and `/sys/devices/pci0000:00/0000:00:19.0/dma/dma3chan1/bytes_transferred`
contains "0", so `idma64` seems to be actually not in use and the only
module that uses these interrupts is the `i2c_designware` at the IRQ #27.

Kernel log (dmesg) shows the following lines:

```
RSP: 0018:ffffa7d5001b7e80 EFLAGS: 00000246
RAX: ffff93ab5f700000 RBX: ffff93ab5f761738 RCX: 000000000000001f
RDX: 0000000000000002 RSI: 0000000033483483 RDI: 0000000000000000
RBP: 0000000000000001 R08: 000004c7d586da52 R09: 0000000000000007
R10: 000000000000002a R11: ffff93ab5f744f04 R12: ffffffffb964fe60
R13: 000004c7d586da52 R14: 0000000000000001 R15: 0000000000000000
 cpuidle_enter+0x2d/0x40
 do_idle+0x1ad/0x210
 cpu_startup_entry+0x29/0x30
 start_secondary+0x11e/0x140
 common_startup_64+0x13e/0x141
 </TASK>
handlers:
[<00000000fa02aea8>] idma64_irq [idma64]
[<00000000d22a6968>] i2c_dw_isr
Disabling IRQ #27
```

Looking to the `i2c_dw_isr` routine source (located at the
`drivers/i2c/busses/i2c-designware-master.c` file) we can see the following
code:

```
static irqreturn_t i2c_dw_isr(int this_irq, void *dev_id)
{
        struct dw_i2c_dev *dev = dev_id;
        unsigned int stat, enabled;

        regmap_read(dev->map, DW_IC_ENABLE, &enabled);
        regmap_read(dev->map, DW_IC_RAW_INTR_STAT, &stat);
        if (!enabled || !(stat & ~DW_IC_INTR_ACTIVITY))
                return IRQ_NONE;
        if (pm_runtime_suspended(dev->dev) || stat == GENMASK(31, 0))
                return IRQ_NONE;

        . . . . .

        return IRQ_HANDLED;
}
```

So looks like interrupt comes, `i2c_dw_isr` cannot recognize it as
its own (which BTW may be normal; due to the very asynchronous nature
of interrupts delivery, spurious interrupts may sometimes happen) and
returns `IRQ_NONE` which eventually causes kernel to consider the
interrupt unhandled and disable it. As result, the touchpad (and
entire I2C stack actually, but touchpad is very noticeable) stops working.

We have coughs this issue in the ROSA linux with kernel 6.12.4 and
it still exists in the 6.12.10.

This issue didn't exist in the 6.6.47 kernel.

The very similar issue was reported for the Arch linux against the
6.12.8 kernel:

  * https://bbs.archlinux.org/viewtopic.php?id=302348

## The solution

This simple module registers itself as a handler of all IRQs, used by
I2C controllers installed into the system.

The added interrupt handler does actually nothing, but always returns
IRQ_HANDLED, so effectively preventing kernel from disabling these
interrupts.

Please notice, that doing so might yield one of two results:

  * it could fix the problem, in case that unhanded interrupt detection
    is false positive, as in our case
  * or it could cause interrupt storm, when the same interrupt comes
    again and again and nobody recognizes and handles it (this is why
    kernel automatically disables unhanded interrupts it detects).

In our case, the solution works reliable and fixes initial problem.

<!-- vim:ts=8:sw=4:et:textwidth=72
-->
