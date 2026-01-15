This is driver for devices like Advantech EKI-152x or EKI-136x for FreeBSD.

This driver similar to Advantech VCOM driver for Linux.

This is driver written on Free Pascal and creates /dev/ttyADVx device files.

This is driver uses /etc/advttyd.conf as configuration file.

Please set Advantech EKI-152x or EKI-136x devices to USDG Data Mode for using the driver.

Checked on Advantech EKI-1362-CE.

Compiled file in current directory for FreeBSD 15.0 RELEASE, but could be compiled for any FreeBSD version using Free Pascal.

Supports logging to adv_eki.log file (disabled by default) and to syslog (enabled by default).

Logging way may be changed using directives of compiler with recompilation of the source code.
