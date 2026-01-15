This is driver for devices like Advantech EKI-152x or EKI-136x for FreeBSD.

The driver does similar functions like Advantech VCOM driver for Linux.

This is driver creates /dev/ttyADVx device files as serial devices using pty.

The driver uses /etc/advttyd.conf as configuration file.

Please set Advantech EKI-152x or EKI-136x devices to **USDG Data Mode** for using the driver.

The driver was checked on Advantech EKI-1362-CE.

Compiled file in current directory for FreeBSD 15.0 RELEASE, but could be compiled for any FreeBSD version using Free Pascal.

Supports logging to adv_eki.log file (disabled by default) and to syslog (enabled by default).

Logging way may be changed using directives of compiler with next recompilation of the source code.
