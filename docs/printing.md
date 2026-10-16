# Printing

`./install.sh --printing` installs CUPS (`cups`, `cups-client`; **no avahi, no cups-browsed**, so printers are neither discovered
nor shared on their own), adds you to the `lpadmin` group (applies after the next login) and creates **one queue** from the
`[printing]` section of `~/.config/hyprdeb/settings.toml`. The queue is not shared on the network. Running it again checks the
queue and only changes it when the address or the driver differs.

```toml
[printing]
printer_name = "Office"                     # letters, digits, _ and - (the CUPS queue name)
printer_uri  = "ipp://192.0.2.20/ipp/print" # socket://HOST[:9100], ipp://HOST[:port]/path or ipps://...
driver       = "everywhere"                 # "everywhere" or "canon-lbp6030"; or ppd = "/path/to.ppd" instead
default      = true                         # optional: make it the default printer
```

## Choosing the driver

| You have | Set | What happens |
|---|---|---|
| A network printer that speaks IPP (most made since about 2015, "AirPrint" or "Mopria") | `printer_uri = "ipp://HOST/ipp/print"` | `lpadmin -m everywhere`: CUPS asks the printer for its capabilities, nothing to download |
| Any printer whose PPD file is already on this machine | `ppd = "/usr/share/cups/model/your.ppd"` (+ `printer_uri`) | `lpadmin -P FILE`; the stage stops before installing anything if the file is missing |
| A Canon LBP6030 without IPP (see below) | `printer_uri = "socket://HOST:9100"`, `driver = "canon-lbp6030"` | Canon's own PPD and filter, over the raw port |

`driver` and `ppd` are mutually exclusive. `driver = "everywhere"` needs an `ipp://` or `ipps://` address and
`canon-lbp6030` a `socket://` one; anything else is a validation error. If neither key is set, the address decides: `ipp`/`ipps`
means `everywhere`, `socket://` means `canon-lbp6030` (the behaviour before the `driver` key existed).

`hyprdeb check` validates the section without touching anything.

## Day to day

```bash
hyprdeb print status [--json]   # settings, driver, CUPS, queue, printer reachable, jobs (read-only; exit 0 fine, 1 a check failed)
hyprdeb print jobs [--json]     # waiting jobs
hyprdeb print cancel JOB_ID
hyprdeb print testpage --yes    # uses one sheet of paper, only with --yes
```

The same checks are on the Printers page of the settings window. A printer that is off or asleep is only a warning: jobs wait in
the queue.

## Example: Canon LBP6030w (raw port, proprietary driver)

The Canon LBP6030w has no IPP/AirPrint, so its queue needs Canon's own driver. That driver is proprietary and **is never in this
repository and never downloaded by the installer**: download Canon's Linux driver package yourself and install the `.deb`
(`cnrdrvcups-ufr2lt-uk`, which puts the PPD at `/usr/share/cups/model/CNRCUPSLBP6030ZNK.ppd` and the filter at
`/usr/lib/cups/filter/rastertosfp`). The stage then checks the package, the PPD and, with `ldd`, that the filter has no unresolved
libraries *before* it configures anything. `libcupsimage2t64` is installed for the filter (the Canon package declares no
dependencies). Use `socket://HOST:9100`, the printer's raw port.

## Removing

`lpadmin -x QUEUE` removes the queue; `sudo systemctl disable --now cups` stops CUPS.
