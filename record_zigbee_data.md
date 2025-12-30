# How to Record Your Own Data Using a Zigbee Sniffer

### 1. Install Wireshark and TShark
First, ensure that both Wireshark and TShark (the command-line version of Wireshark) are installed. You can download them from the [Wireshark official website](https://www.wireshark.org/download.html) and follow the installation instructions for your operating system.

### 2. Build and Install the Wireshark Plugin
To capture data from the Zigbee USB sniffer, you'll need to build and install a custom Wireshark plugin. Follow the instructions from the repository below to do this:

- Clone the repository: [https://github.com/andrebdo/wireshark-cc2531](https://github.com/andrebdo/wireshark-cc2531).
- Follow the steps in the repository to build the plugin and integrate it into your Wireshark installation.

```bash
git clone https://github.com/andrebdo/wireshark-cc2531
cd wireshark-cc2531
# Follow the instructions in the README to build and install the plugin.
```

### 3. Connect the TI CC2531 USB Zigbee Sniffer
After installing the plugin, connect your **TI CC2531 USB Zigbee sniffer** to your machine.

### 4. Verify Sniffer Availability in Wireshark
When you launch Wireshark, you should see an option for the TI CC2531 sniffer under the available capture interfaces. Select it to verify that it's capturing data.

- If no data appears, check your plugin installation or make sure the sniffer is properly connected.

### 5. Use the `recorder.sh` Script to Record Your Dataset
For reliable dataset recording, you can use the `scripts/recorder.sh` script provided in this repository. This script helps automate the data capture process and ensures that the data is recorded properly.

Run the script using:

```bash
bash scripts/recorder.sh
```

This will start capturing data using the sniffer and create a dataset that you can later analyze in Wireshark.

#### Capturing on Multiple Channels
Zigbee uses channels **11–26**. If you have multiple sniffer dongles connected, you can capture several channels in parallel:

```bash
# Example with two sniffers covering channels 15 and 20
bash scripts/recorder.sh --interfaces cc2531,cc2531_1 --channels 15,20
```

To attempt capturing on every Zigbee channel, supply interfaces for each available dongle and let the script map them in order:

```bash
bash scripts/recorder.sh --interfaces cc2531,cc2531_1,cc2531_2,cc2531_3 --all-channels
```

If fewer interfaces are provided than channels requested, the script will start as many captures as there are dongles and warn about the remaining channels. Use `--channel-command "iwpan dev {iface} set channel 0 {channel}"` (or another command suited to your hardware) if your sniffer requires an explicit channel configuration before capture starts.

By following these steps, you can successfully record and capture your own Zigbee network data using the TI CC2531 sniffer and Wireshark.
