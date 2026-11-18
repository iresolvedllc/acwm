---
title: IPC
description: Control acwm programmatically using acwm-msg.
---

# acwm-msg(1) - User Manual

`acwm-msg` is the command-line interface for the ACWM compositor's Inter-Process Communication (IPC) system. It allows users and scripts to query the state of the compositor or subscribe to real-time events.

## SYNOPSIS
`acwm-msg <command> [arguments...]`

## DESCRIPTION
`acwm-msg` acts as a client that connects to the ACWM compositor via a Unix domain socket defined by the `ACWM_INSTANCE_SIGNATURE` environment variable. It supports two primary modes of operation:
1. **One-shot Request (`get`)**: Sends a query to the compositor, receives a single JSON response, and terminates.
2. **Persistent Stream (`watch`)**: Subscribes to a specific state, receiving continuous JSON updates whenever that state changes.

## ENVIRONMENT VARIABLES
* **`ACWM_INSTANCE_SIGNATURE`**: Must be set to the path of the Unix socket created by the running ACWM instance. This is typically handled automatically when running `acwm-msg` from within a terminal spawned by the compositor.

## COMMANDS

### GET (One-Shot Queries)
| Command | Description |
| :--- | :--- |
| `get version` | Returns the current version of the compositor. |
| `get cursorpos` | Returns the global pointer position (`x`, `y`) and the monitor under it. |
| `get keymode` | Returns the current active keyboard mode (e.g., normal, insert). |
| `get keyboardlayout` | Returns the active XKB layout (abbreviated). |
| `get monitor <name>` | Returns full JSON details for a specific monitor. |
| `get focusing-client` | Returns full JSON details for the client currently in focus. |
| `get client <id>` | Returns full JSON details for a client with the given ID. |
| `get tag <mon> <idx>` | Queries status of a specific tag on a monitor. |
| `get tags <mon>` | Returns a JSON object containing the status of all tags on a monitor. |
| `get all-clients` | Returns a JSON array of all active clients. |
| `get all-monitors` | Returns a JSON array of all connected monitors. |
| `get all-devices` | Returns a JSON array of all physical input devices, grouped by libinput device group (`name`, `types`, `identifier`, `vendor`, `product`, `interfaces`, `matched`). |
| `get all-layers` | Returns a JSON array of all open layer surfaces (`monitor`, `layer`, `name`). |
| `get all-tags` | Returns a JSON object containing the status of all tags. |
| `get last_open_surface [<mon>]` | Returns the last focused surface name for a monitor,if the mon not set, it will get current monitor. |

*Example:*
```bash
acwm-msg get monitor eDP-1
acwm-msg get all-clients
acwm-msg get all-monitors
acwm-msg get all-devices
acwm-msg get all-layers
acwm-msg get cursorpos
```

### WATCH (Event Subscription)
Subscribes the client to real-time updates. When the state changes, the server pushes a new JSON object to the output stream.

* `watch monitor <name>`
* `watch focusing-client`
* `watch client <id>`
* `watch tags <mon_name>`
* `watch all-monitors`
* `watch all-tags`
* `watch all-clients`
* `watch all-devices` — streams the last input device (`name`, `type`) that triggered an event
* `watch keymode`
* `watch keyboardlayout`
* `watch last_open_surface [<mon_name>]`

*Example:*
```bash
# watch all monitors
acwm-msg watch all-monitors
# watch all tags
acwm-msg watch all-tags
```

### DISPATCH
Allows sending commands to the compositor to alter its state.
* `dispatch <func_name>,[args...] [client,<id>]`

*Example:* 
```bash   
# operate specific client by id
acwm-msg dispatch exchange_client,left client,375
# operate current client
acwm-msg dispatch exchange_client,left
````
