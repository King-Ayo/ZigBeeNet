#!/bin/bash

set -o pipefail

DEFAULT_DURATION_SECONDS=3600
DEFAULT_CHANNEL=11
ALL_CHANNELS=({11..26})
OUTPUT_PREFIX="zigbee"
CHANNEL_COMMAND=""
OUTPUT_DIR="."

print_usage() {
    cat <<'EOF'
Usage: recorder.sh [options]

Options:
  -i, --interfaces   Comma-separated list of capture interfaces (default: cc2531).
  -c, --channels     Comma-separated list or ranges of channels (e.g. 11,15-18).
  -a, --all-channels Capture on every Zigbee channel (11-26).
  -d, --duration     Duration (seconds) for each pcap file before rotation (default: 3600).
  -o, --output-dir   Directory for pcap output files (default: current directory).
  -p, --prefix       File name prefix (default: zigbee).
  --channel-command  Command to set a channel before capture.
                     Use {iface} and {channel} placeholders.
                     Example: --channel-command "iwpan dev {iface} set channel 0 {channel}"
  -h, --help         Show this help message.

Examples:
  # Single dongle on channel 11 (default behaviour)
  bash scripts/recorder.sh

  # Two dongles on channels 15 and 20
  bash scripts/recorder.sh --interfaces cc2531,cc2531_1 --channels 15,20

  # Use all available channels with four dongles (channels assigned in order)
  bash scripts/recorder.sh --interfaces cc2531,cc2531_1,cc2531_2,cc2531_3 --all-channels
EOF
}

parse_channels() {
    local input="$1"
    local -n output_array=$2

    IFS=',' read -ra channel_parts <<< "$input"
    for part in "${channel_parts[@]}"; do
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start=${BASH_REMATCH[1]}
            local end=${BASH_REMATCH[2]}
            if (( start > end )); then
                echo "Invalid range: $part" >&2
                exit 1
            fi
            for ((c=start; c<=end; c++)); do
                output_array+=("$c")
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            output_array+=("$part")
        else
            echo "Invalid channel format: $part" >&2
            exit 1
        fi
    done
}

configure_channel() {
    local iface="$1"
    local channel="$2"

    if [[ -n "$CHANNEL_COMMAND" ]]; then
        local cmd=${CHANNEL_COMMAND//\{iface\}/$iface}
        cmd=${cmd//\{channel\}/$channel}
        echo "Configuring ${iface} to channel ${channel} using: ${cmd}"
        # shellcheck disable=SC2086 # Intentional word splitting to allow user-provided commands
        eval $cmd || echo "Channel command failed for ${iface} (channel ${channel}). Continuing with capture..." >&2
        return
    fi

    if command -v iwpan >/dev/null 2>&1 && iwpan dev "$iface" info >/dev/null 2>&1; then
        echo "Setting ${iface} to channel ${channel} via iwpan"
        ip link set "$iface" down >/dev/null 2>&1
        if iwpan dev "$iface" set channel 0 "$channel" >/dev/null 2>&1; then
            ip link set "$iface" up >/dev/null 2>&1
            return
        fi
    fi

    echo "Unable to auto-configure ${iface} to channel ${channel}. Please ensure the interface is tuned manually." >&2
}

start_capture_loop() {
    local iface="$1"
    local channel="$2"
    local duration="$3"
    local restart_count=1
    local safe_iface="${iface//[^a-zA-Z0-9_-]/_}"

    while true; do
        local timestamp
        timestamp=$(date +%Y%m%d%H%M%S)
        local output_file="${OUTPUT_DIR}/${OUTPUT_PREFIX}_ch${channel}_${safe_iface}_${timestamp}.pcap"

        echo "Starting tshark on ${iface} (channel ${channel}) -> ${output_file} (attempt ${restart_count})"
        configure_channel "$iface" "$channel"
        ((restart_count++))
        tshark -i "$iface" -b duration:"$duration" -w "$output_file" -I
        echo "tshark on ${iface} (channel ${channel}) stopped. Restarting..."
    done
}

main() {
    local interfaces_arg=""
    local channels_arg=""
    local use_all_channels=false
    local duration="$DEFAULT_DURATION_SECONDS"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--interfaces)
                interfaces_arg="$2"
                shift 2
                ;;
            -c|--channels)
                channels_arg="$2"
                shift 2
                ;;
            -a|--all-channels)
                use_all_channels=true
                shift
                ;;
            -d|--duration)
                duration="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -p|--prefix)
                OUTPUT_PREFIX="$2"
                shift 2
                ;;
            --channel-command)
                CHANNEL_COMMAND="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                print_usage
                exit 1
                ;;
        esac
    done

    if ! command -v tshark >/dev/null 2>&1; then
        echo "tshark is required but not found. Please install tshark before running this script." >&2
        exit 1
    fi

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        echo "Creating output directory: ${OUTPUT_DIR}"
        mkdir -p "$OUTPUT_DIR"
    fi

    local interfaces=()
    if [[ -n "$interfaces_arg" ]]; then
        IFS=',' read -ra interfaces <<< "$interfaces_arg"
    else
        interfaces=("cc2531")
    fi

    local channels=()
    if [[ "$use_all_channels" == true ]]; then
        channels=("${ALL_CHANNELS[@]}")
    elif [[ -n "$channels_arg" ]]; then
        parse_channels "$channels_arg" channels
    else
        channels=("$DEFAULT_CHANNEL")
    fi

    for channel in "${channels[@]}"; do
        if (( channel < 11 || channel > 26 )); then
            echo "Channel ${channel} is outside the Zigbee range (11-26)." >&2
            exit 1
        fi
    done

    if (( ${#interfaces[@]} < ${#channels[@]} )); then
        echo "Warning: ${#channels[@]} channels requested but only ${#interfaces[@]} sniffers provided." >&2
        echo "         Captures will start for the first ${#interfaces[@]} channels. Provide more sniffers to cover all channels." >&2
        channels=("${channels[@]:0:${#interfaces[@]}}")
    fi

    echo "Starting captures:"
    echo "  Interfaces : ${interfaces[*]}"
    echo "  Channels   : ${channels[*]}"
    echo "  Duration   : ${duration}s per file"
    echo "  Output dir : ${OUTPUT_DIR}"
    echo "  File prefix: ${OUTPUT_PREFIX}"

    declare -a pids=()
    for idx in "${!channels[@]}"; do
        start_capture_loop "${interfaces[$idx]}" "${channels[$idx]}" "$duration" &
        pids+=("$!")
    done

    trap 'echo "Stopping captures..."; kill "${pids[@]}" 2>/dev/null; wait; exit 0' INT TERM
    wait
}

main "$@"
