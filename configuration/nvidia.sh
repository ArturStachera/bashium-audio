#!/bin/bash

print_header(){
    cat <<'EOF'
+----------------------------------------------------------+
|                    BASHIUM NVIDIA SETUP                  |
+----------------------------------------------------------+
EOF
}

ask_question(){
    local answer
    printf "\e[33m%s\e[0m (y/n): " "$1"
    while true; do
        read -rsn1 answer
        if [[ $answer =~ ^[yYnN]$ ]]; then
            printf "%s " "$answer"
            break
        fi
    done
    echo ""
    if [[ $answer == [yY] ]]; then
        return 0
    else
        return 1
    fi
}

print_info(){
    printf "\e[36m[INFO]\e[0m %s\n" "$1" >&2
}

print_warn(){
    printf "\e[33m[WARN]\e[0m %s\n" "$1" >&2
}

print_err(){
    printf "\e[31m[ERROR]\e[0m %s\n" "$1" >&2
}

print_ok(){
    printf "\e[32m[ OK ]\e[0m %s\n" "$1" >&2
}

if [[ $EUID -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
fi

get_codename(){
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        if [[ -n ${VERSION_CODENAME:-} ]]; then
            echo "$VERSION_CODENAME"
            return 0
        fi
    fi
    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -sc
        return 0
    fi
    echo ""
}

get_debian_track(){
    local policy
    policy=$(apt-cache policy 2>/dev/null || true)
    if echo "$policy" | grep -q 'a=unstable'; then
        echo "unstable"
        return 0
    fi
    if echo "$policy" | grep -q 'a=testing'; then
        echo "testing"
        return 0
    fi
    if echo "$policy" | grep -q 'a=stable'; then
        echo "stable"
        return 0
    fi
    echo "unknown"
}

has_backports_enabled(){
    if grep -REqs -- '^[[:space:]]*deb[[:space:]].*-backports([[:space:]]|$)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        return 0
    fi
    return 1
}

has_bashium_backports(){
    [[ -f /etc/apt/sources.list.d/bashium-backports.list ]]
}

has_component_enabled(){
    local component="$1"
    if [[ -z $component ]]; then
        return 1
    fi

    if grep -REqs -- "^[[:space:]]*deb[[:space:]].*([[:space:]]|^)${component}([[:space:]]|$)" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        return 0
    fi

    if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
        if grep -Eq "^[[:space:]]*Components:.*([[:space:]]|^)${component}([[:space:]]|$)" /etc/apt/sources.list.d/debian.sources 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

has_nonfree_enabled(){
    has_component_enabled "non-free"
}

has_nonfree_firmware_enabled(){
    has_component_enabled "non-free-firmware"
}

has_contrib_enabled(){
    has_component_enabled "contrib"
}

has_any_nonfree_flavor_enabled(){
    if has_nonfree_enabled || has_nonfree_firmware_enabled; then
        return 0
    fi
    return 1
}

apt_update(){
    # Always redirect to stderr — apt_update is called from inside find_best_nvidia_package
    # which is invoked via $() capture; stdout leaking here would corrupt the captured value.
    DEBIAN_FRONTEND=noninteractive apt-get update >&2
}

has_nvidia_gpu(){
    if ! command -v lspci >/dev/null 2>&1; then
        return 1
    fi
    lspci -nn | grep -qi "nvidia"
}

ensure_non_free_components(){
    local changed=false

    if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
        if ! grep -Eq "^[[:space:]]*Components:.*([[:space:]]|^)contrib([[:space:]]|$)" /etc/apt/sources.list.d/debian.sources; then
            sed -i -E 's/^(Components:[[:space:]]*)(.*)$/\1\2 contrib/' /etc/apt/sources.list.d/debian.sources
            changed=true
        fi
        if ! grep -Eq "^[[:space:]]*Components:.*([[:space:]]|^)non-free([[:space:]]|$)" /etc/apt/sources.list.d/debian.sources; then
            sed -i -E 's/^(Components:[[:space:]]*)(.*)$/\1\2 non-free/' /etc/apt/sources.list.d/debian.sources
            changed=true
        fi
        if ! grep -Eq "^[[:space:]]*Components:.*([[:space:]]|^)non-free-firmware([[:space:]]|$)" /etc/apt/sources.list.d/debian.sources; then
            sed -i -E 's/^(Components:[[:space:]]*)(.*)$/\1\2 non-free-firmware/' /etc/apt/sources.list.d/debian.sources
            changed=true
        fi
    fi

    if [[ -f /etc/apt/sources.list ]]; then
        if grep -Eq '^[[:space:]]*deb[[:space:]].*[[:space:]]main([[:space:]]|$)' /etc/apt/sources.list; then
            if ! grep -Eq '^[[:space:]]*deb[[:space:]].*[[:space:]]main.*([[:space:]]|^)contrib([[:space:]]|$)' /etc/apt/sources.list; then
                sed -i -E '/^[[:space:]]*deb[[:space:]].*[[:space:]]main([[:space:]]|$)/ s/$/ contrib/' /etc/apt/sources.list
                changed=true
            fi
            if ! grep -Eq '^[[:space:]]*deb[[:space:]].*[[:space:]]main.*([[:space:]]|^)non-free([[:space:]]|$)' /etc/apt/sources.list; then
                sed -i -E '/^[[:space:]]*deb[[:space:]].*[[:space:]]main([[:space:]]|$)/ s/$/ non-free/' /etc/apt/sources.list
                changed=true
            fi
            if ! grep -Eq '^[[:space:]]*deb[[:space:]].*[[:space:]]main.*([[:space:]]|^)non-free-firmware([[:space:]]|$)' /etc/apt/sources.list; then
                sed -i -E '/^[[:space:]]*deb[[:space:]].*[[:space:]]main([[:space:]]|$)/ s/$/ non-free-firmware/' /etc/apt/sources.list
                changed=true
            fi
        fi
    fi

    if [[ $changed == true ]]; then
        apt_update
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  GPU Architecture Detection
# ══════════════════════════════════════════════════════════════════════════════

detect_gpu_arch(){
    local pci_ids
    pci_ids=$(lspci -nn 2>/dev/null | grep -i 'nvidia' | grep -ioP '10de:([0-9a-f]{4})' | cut -d: -f2 | tr '[:upper:]' '[:lower:]')

    if [[ -z $pci_ids ]]; then
        echo "unknown"
        return
    fi

    local dev_id
    dev_id=$(echo "$pci_ids" | head -n1)
    local id_int=$((16#$dev_id))

    # Ada Lovelace (AD10x): 0x2680+
    if (( id_int >= 0x2680 )); then echo "ada"; return; fi
    # Ampere (GA10x): 0x2200-0x267F
    if (( id_int >= 0x2200 && id_int < 0x2680 )); then echo "ampere"; return; fi
    # Turing (TU10x): 0x1E00-0x21FF
    if (( id_int >= 0x1E00 && id_int < 0x2200 )); then echo "turing"; return; fi
    # Volta (GV100): 0x1D81-0x1DFF
    if (( id_int >= 0x1D81 && id_int <= 0x1DFF )); then echo "volta"; return; fi
    # Pascal (GP10x): 0x1B00-0x1D80, 0x15F0-0x15FF
    if (( id_int >= 0x1B00 && id_int <= 0x1D80 )); then echo "pascal"; return; fi
    if (( id_int >= 0x15F0 && id_int <= 0x15FF )); then echo "pascal"; return; fi
    # Maxwell (GM1xx/2xx): 0x1340-0x17FF
    if (( id_int >= 0x1340 && id_int <= 0x17FF )); then echo "maxwell"; return; fi
    # Kepler (GK1xx): 0x0FC0-0x133F
    if (( id_int >= 0x0FC0 && id_int <= 0x133F )); then echo "kepler"; return; fi
    # Fermi and older
    if (( id_int < 0x0FC0 )); then echo "fermi_or_older"; return; fi

    echo "unknown"
}

# Returns 0 if GPU architecture needs a legacy driver (Maxwell/Pascal/Volta)
is_legacy_gpu(){
    local arch="$1"
    case "$arch" in
        kepler|maxwell|pascal|volta|fermi_or_older)
            return 0
            ;;
    esac
    return 1
}

# Max supported driver branch per GPU architecture
max_driver_branch_for_arch(){
    local arch="$1"
    case "$arch" in
        fermi_or_older) echo "390" ;;
        kepler)         echo "470" ;;
        maxwell|pascal|volta) echo "580" ;;
        *)              echo "9999" ;; # current GPUs — any branch
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
#  Kernel Version Helpers
# ══════════════════════════════════════════════════════════════════════════════

get_kernel_version(){
    uname -r | grep -oP '^[0-9]+\.[0-9]+'
}

get_kernel_major(){
    uname -r | grep -oP '^[0-9]+' | head -n1
}

get_kernel_minor(){
    uname -r | grep -oP '^[0-9]+\.([0-9]+)' | cut -d. -f2
}

# Minimum driver branch required for a given kernel
min_driver_branch_for_kernel(){
    local kmaj kmin
    kmaj=$(get_kernel_major)
    kmin=$(get_kernel_minor)

    if (( kmaj >= 7 )); then
        echo "580"
    elif (( kmaj == 6 && kmin >= 16 )); then
        echo "570"
    elif (( kmaj == 6 && kmin >= 12 )); then
        echo "550"
    else
        echo "470"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  Driver Package Helpers
# ══════════════════════════════════════════════════════════════════════════════

# Extract the major version number (e.g. 550) from an apt candidate string
get_pkg_candidate_version(){
    local pkg="$1"
    # Force English locale — on non-English systems apt-cache policy outputs
    # localised field names (e.g. "Kandydująca:" in Polish) which breaks grep 'Candidate:'
    LANG=C apt-cache policy "$pkg" 2>/dev/null | grep 'Candidate:' | awk '{print $2}'
}

get_version_major(){
    local ver="$1"
    echo "$ver" | grep -oP '^[0-9]+' | head -n1
}

# Check if a given package is installable (has a candidate that is not "(none)")
is_pkg_available(){
    local pkg="$1"
    local cand
    cand=$(get_pkg_candidate_version "$pkg")
    [[ -n $cand && $cand != "(none)" ]]
}

# Check if candidate version from a specific source (e.g. backports) exists
has_pkg_in_backports(){
    local pkg="$1"
    local codename="$2"
    apt-cache policy "$pkg" 2>/dev/null | grep -q "${codename}-backports"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Smart Backports Management
# ══════════════════════════════════════════════════════════════════════════════

# Determine if backports should be used for the given track
should_use_backports(){
    local track="$1"
    case "$track" in
        stable)
            # Stable often needs backports for newer driver versions
            return 0
            ;;
        testing)
            # Testing usually has recent enough packages; backports
            # are only needed when the required package is missing entirely
            return 1
            ;;
        unstable)
            # Unstable never has backports
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Enable backports managed by bashium
enable_bashium_backports(){
    local codename="$1"
    local backports_file="/etc/apt/sources.list.d/bashium-backports.list"

    if [[ -z $codename ]]; then
        print_warn "Cannot enable backports: codename unknown."
        return 1
    fi

    if [[ -f $backports_file ]] && grep -q "${codename}-backports" "$backports_file" 2>/dev/null; then
        print_info "Bashium backports already configured for ${codename}-backports."
        return 0
    fi

    print_info "Enabling ${codename}-backports..."
    echo "deb http://deb.debian.org/debian ${codename}-backports main contrib non-free non-free-firmware" > "$backports_file"
    apt_update
    print_ok "Backports enabled: ${codename}-backports"
    return 0
}

# Remove bashium-managed backports (cleanup)
disable_bashium_backports(){
    local backports_file="/etc/apt/sources.list.d/bashium-backports.list"
    if [[ -f $backports_file ]]; then
        rm -f "$backports_file"
        apt_update
        print_ok "Bashium-managed backports removed."
    fi
}

# Ensure backports are available if needed, enable only when necessary
ensure_backports_if_needed(){
    local pkg="$1"
    local codename="$2"
    local track="$3"

    # Never backports on unstable
    if [[ $track == "unstable" ]]; then
        return 1
    fi

    # On stable: always try backports if the package is missing or version is too old
    if [[ $track == "stable" ]]; then
        if ! is_pkg_available "$pkg"; then
            print_info "Package '$pkg' not found in main repos. Trying backports..."
            enable_bashium_backports "$codename"
            return $?
        fi
        # On stable, also prefer backports if available (newer driver)
        if ! has_backports_enabled; then
            enable_bashium_backports "$codename"
        fi
        return 0
    fi

    # On testing: only enable backports if the package is truly missing
    if [[ $track == "testing" ]]; then
        if is_pkg_available "$pkg"; then
            print_info "Package '$pkg' available in main repos (testing). Backports not needed."
            return 1
        fi
        print_info "Package '$pkg' not found in testing repos. Trying backports..."
        enable_bashium_backports "$codename"
        return $?
    fi

    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
#  Smart Driver Selection
# ══════════════════════════════════════════════════════════════════════════════

find_best_nvidia_package(){
    local codename="$1"
    local track="$2"
    local gpu_arch="$3"

    local max_branch min_branch
    max_branch=$(max_driver_branch_for_arch "$gpu_arch")
    min_branch=$(min_driver_branch_for_kernel)

    print_info "GPU architecture: $gpu_arch"
    print_info "Max driver branch for GPU: $max_branch"
    print_info "Min driver branch for kernel $(uname -r): $min_branch"

    # Check if there is a valid range at all
    if (( min_branch > max_branch )); then
        print_err "COMPATIBILITY CONFLICT DETECTED!"
        print_err "Your GPU ($gpu_arch) supports drivers up to branch $max_branch,"
        print_err "but kernel $(uname -r) requires at least branch $min_branch."
        print_err ""
        print_err "This means no NVIDIA driver version supports both your GPU and kernel."
        print_err "Options:"
        print_err "  1) Boot an older kernel compatible with the ${max_branch}.xx driver"
        print_err "  2) Upgrade to a GPU supported by the ${min_branch}.xx+ driver branch"
        echo "" >&2
        return 1
    fi

    # Try nvidia-detect first
    if ! command -v nvidia-detect >/dev/null 2>&1; then
        # Redirect stdout to stderr — this function's stdout is captured by the caller
        # via pkg=$(find_best_nvidia_package ...), so any apt output on stdout would
        # corrupt $pkg. Sending it to stderr keeps it visible on terminal but uncaptured.
        DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-detect >&2 || true
    fi

    local detect_pkg=""
    if command -v nvidia-detect >/dev/null 2>&1; then
        detect_pkg=$(nvidia-detect 2>/dev/null | grep -oE 'nvidia-(driver(-[0-9]+)?|legacy-[0-9]+xx-driver)' | head -n1)
        if [[ -n $detect_pkg ]]; then
            print_info "nvidia-detect recommends: $detect_pkg"
        fi
    fi

    # Build a list of candidate packages to try, ordered by preference
    local candidates=()

    # If GPU is legacy, try legacy package names first
    if is_legacy_gpu "$gpu_arch"; then
        candidates+=("nvidia-legacy-${max_branch}xx-driver")
        # Also try without the 'xx' suffix variants
        candidates+=("nvidia-legacy-${max_branch}-driver")
    fi

    # nvidia-detect fast path: trust its recommendation and only verify max_branch (hardware
    # limit). We deliberately skip the min_branch check here — nvidia-detect already accounts
    # for kernel compatibility, while our min_branch heuristic can lag behind what Debian
    # actually packages. We also try backports FIRST, before checking availability, because
    # on Debian testing the package may not yet have migrated to main repos.
    if [[ -n $detect_pkg ]]; then
        # Enable backports upfront so is_pkg_available can see the full candidate set
        ensure_backports_if_needed "$detect_pkg" "$codename" "$track" || true

        if is_pkg_available "$detect_pkg"; then
            local det_ver det_major
            det_ver=$(get_pkg_candidate_version "$detect_pkg")
            det_major=$(get_version_major "$det_ver")
            if [[ -n $det_major ]] && (( det_major <= max_branch )); then
                print_ok "Trusting nvidia-detect recommendation: $detect_pkg ($det_ver)"
                echo "$detect_pkg"
                return 0
            else
                print_warn "nvidia-detect recommends $detect_pkg ($det_ver) but version exceeds max branch ${max_branch} for $gpu_arch GPU — skipping fast path."
            fi
        else
            print_warn "nvidia-detect recommends '$detect_pkg' but it cannot be found in any configured repo (including backports)."
        fi
    fi

    # Add nvidia-detect recommendation to the fallback list as well
    if [[ -n $detect_pkg ]]; then
        candidates+=("$detect_pkg")
    fi

    # Generic fallback
    candidates+=("nvidia-driver")

    # Try each candidate
    for pkg in "${candidates[@]}"; do
        # First check in current repos
        if is_pkg_available "$pkg"; then
            local cand_ver cand_major
            cand_ver=$(get_pkg_candidate_version "$pkg")
            cand_major=$(get_version_major "$cand_ver")

            if [[ -z $cand_major ]]; then
                continue
            fi

            # Validate: driver must be >= min_branch AND <= max_branch
            if (( cand_major >= min_branch && cand_major <= max_branch )); then
                print_ok "Found compatible package: $pkg ($cand_ver)"
                echo "$pkg"
                return 0
            else
                print_warn "Package '$pkg' version $cand_ver (branch $cand_major) is not compatible."
                if (( cand_major < min_branch )); then
                    print_warn "  -> Too old for kernel $(uname -r) (need >= ${min_branch}.xx)"
                fi
                if (( cand_major > max_branch )); then
                    print_warn "  -> Too new for $gpu_arch GPU (need <= ${max_branch}.xx)"
                fi
            fi
        fi

        # Try backports if applicable
        if ensure_backports_if_needed "$pkg" "$codename" "$track"; then
            if is_pkg_available "$pkg"; then
                local bp_ver bp_major
                bp_ver=$(get_pkg_candidate_version "$pkg")
                bp_major=$(get_version_major "$bp_ver")

                if [[ -n $bp_major ]] && (( bp_major >= min_branch && bp_major <= max_branch )); then
                    print_ok "Found compatible package in backports: $pkg ($bp_ver)"
                    echo "$pkg"
                    return 0
                fi
            fi
        fi
    done

    # Nothing found — inform the user
    print_err "No compatible NVIDIA driver package found in repositories."
    print_err "Required: driver branch >= $min_branch and <= $max_branch"
    echo "" >&2
    print_info "You may need to:"
    print_info "  - Wait for your distribution to package a compatible driver version"
    print_info "  - Install the driver manually from nvidia.com (not recommended)"
    print_info "  - Boot an older kernel that works with available driver versions"
    echo "" >&2
    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
#  DKMS Verification & RT Patch
# ══════════════════════════════════════════════════════════════════════════════

# On RT kernels, NVIDIA's dkms.conf contains a BUILD_EXCLUSIVE directive that
# prevents the module from compiling. This function patches it out and rebuilds.
# $1: DKMS module name (e.g. "nvidia")
# $2: DKMS module version (e.g. "560.35.03")
# $3: target kernel (e.g. "6.12.63+deb13-rt-amd64")
patch_dkms_rt_lock(){
    local module_name="$1"
    local module_ver="$2"
    local target_kernel="$3"
    local src_dir="/usr/src/${module_name}-${module_ver}"

    if [[ ! -d $src_dir ]]; then
        print_err "DKMS source directory not found: ${src_dir}"
        print_err "Expected layout: /usr/src/<module>-<version>/dkms.conf"
        return 1
    fi

    if [[ ! -f "${src_dir}/dkms.conf" ]]; then
        print_err "dkms.conf not found inside ${src_dir}"
        return 1
    fi

    print_info "Removing previous broken DKMS build state..."
    dkms remove "${module_name}/${module_ver}" --all 2>/dev/null || true

    # Comment out all BUILD_EXCLUSIVE* directives so the module is allowed to build
    # on RT kernels. NVIDIA uses variants like BUILD_EXCLUSIVE_CONFIG and
    # BUILD_EXCLUSIVE_KERNEL — the pattern must match all of them, not just
    # BUILD_EXCLUSIVE= (which would miss the suffixed variants entirely).
    local be_count
    be_count=$(grep -c '^BUILD_EXCLUSIVE' "${src_dir}/dkms.conf" 2>/dev/null || true)
    if (( be_count > 0 )); then
        sed -i 's/^BUILD_EXCLUSIVE/#BUILD_EXCLUSIVE/' "${src_dir}/dkms.conf"
        # Verify every directive was actually commented out
        local remaining
        remaining=$(grep -c '^BUILD_EXCLUSIVE' "${src_dir}/dkms.conf" 2>/dev/null || true)
        if (( remaining > 0 )); then
            print_err "Patch failed — ${remaining} BUILD_EXCLUSIVE directive(s) still active:"
            grep '^BUILD_EXCLUSIVE' "${src_dir}/dkms.conf" >&2
            return 1
        fi
        print_ok "Patched ${be_count} BUILD_EXCLUSIVE directive(s) in ${src_dir}/dkms.conf"
    else
        print_info "No active BUILD_EXCLUSIVE directives found — may already be patched."
    fi

    print_info "Re-registering DKMS module..."
    dkms add "${module_name}/${module_ver}" 2>/dev/null || true

    print_info "Compiling ${module_name}/${module_ver} for ${target_kernel} — this may take a few minutes..."
    if ! dkms build "${module_name}/${module_ver}" -k "${target_kernel}"; then
        local makelog="/var/lib/dkms/${module_name}/${module_ver}/build/make.log"
        # Check for the PREEMPT_RT sanity check inside NVIDIA driver source (Kbuild).
        # This is a separate, hardcoded refusal that cannot be bypassed via dkms.conf.
        if [[ -f $makelog ]] && grep -q "PREEMPT_RT sanity check" "$makelog"; then
            echo ""
            print_err "NVIDIA driver source refuses to compile on PREEMPT_RT kernels."
            print_err "This is a hardcoded check in the driver Kbuild, independent of dkms.conf."
            print_err "The NVIDIA proprietary driver officially does not support RT kernels."
            echo ""
            print_warn "Your options:"
            print_warn "  1. Use the non-RT variant of kernel 6.12 (recommended)"
            print_warn "     Reboot into the non-RT 6.12 kernel, then run this script again."
            print_warn "  2. Use RT kernel + nouveau (open-source, limited GPU performance, no CUDA)"
            print_warn "  3. Keep both kernels: RT for audio sessions, non-RT for GPU work."
        else
            print_err "Build failed. Log: ${makelog}"
        fi
        return 1
    fi

    if ! dkms install "${module_name}/${module_ver}" -k "${target_kernel}"; then
        print_err "Module built successfully but install step failed."
        return 1
    fi

    print_ok "DKMS module compiled and installed for ${target_kernel}."
    return 0
}

verify_dkms_build(){
    echo ""
    print_info "Verifying DKMS module build status..."

    if ! command -v dkms >/dev/null 2>&1; then
        print_warn "dkms not found, cannot verify module build."
        return 1
    fi

    local running_k
    running_k=$(uname -r)

    local dkms_status
    dkms_status=$(dkms status 2>/dev/null | grep -i nvidia || true)

    if [[ -z $dkms_status ]]; then
        print_warn "No NVIDIA DKMS module found."
        return 1
    fi

    echo "$dkms_status"

    # Parse module name and version upfront — used in all failure branches.
    # Format from dkms status: "nvidia-current/550.163.01: added"
    #                       or "nvidia/560.35.03, 6.12.63+deb13-rt-amd64: installed"
    local nvidia_mod nvidia_ver
    nvidia_mod=$(echo "$dkms_status" | grep -oP '^[a-z][a-z0-9-]*(?=/)' | head -n1)
    nvidia_ver=$(echo "$dkms_status" | grep -oP '(?<=/)[0-9]+\.[0-9]+\.[0-9]+' | head -n1)

    if echo "$dkms_status" | grep -qi ': installed'; then
        print_ok "NVIDIA kernel module built and installed successfully."
        return 0
    elif echo "$dkms_status" | grep -qiE ': added$'; then
        # "added" = module registered in DKMS but postinst never triggered a build
        # (typical when dpkg fails partway through nvidia-kernel-dkms configure step)
        print_warn "DKMS module is registered but has not been built yet."
        print_warn "This usually means dpkg's postinst was interrupted before compilation."
        echo ""
        if [[ -n $nvidia_mod && -n $nvidia_ver ]] && ask_question "Build and install the DKMS module now?"; then
            if is_rt_kernel; then
                print_info "RT kernel detected — patching BUILD_EXCLUSIVE before building."
                patch_dkms_rt_lock "$nvidia_mod" "$nvidia_ver" "$running_k"
                return $?
            else
                print_info "Building ${nvidia_mod}/${nvidia_ver} for ${running_k}..."
                if ! dkms build "${nvidia_mod}/${nvidia_ver}" -k "$running_k"; then
                    print_err "Build failed. Log: /var/lib/dkms/${nvidia_mod}/${nvidia_ver}/build/make.log"
                    return 1
                fi
                if ! dkms install "${nvidia_mod}/${nvidia_ver}" -k "$running_k"; then
                    print_err "Install step failed after successful build."
                    return 1
                fi
                print_ok "DKMS module built and installed for ${running_k}."
                return 0
            fi
        fi
        return 1
    elif echo "$dkms_status" | grep -qiE 'error|broken|build.failed'; then
        print_err "NVIDIA kernel module build FAILED."

        # On RT kernels the likely cause is BUILD_EXCLUSIVE blocking compilation
        if is_rt_kernel && [[ -n $nvidia_mod && -n $nvidia_ver ]]; then
            print_warn "RT kernel detected — BUILD_EXCLUSIVE in dkms.conf likely blocked compilation."
            if ask_question "Patch dkms.conf and rebuild? (recommended)"; then
                patch_dkms_rt_lock "$nvidia_mod" "$nvidia_ver" "$running_k"
                return $?
            fi
        else
            print_err "Check build log: /var/lib/dkms/${nvidia_mod:-nvidia}/${nvidia_ver:-?}/build/make.log"
            echo ""
            if [[ -n $nvidia_mod && -n $nvidia_ver ]] && ask_question "Attempt plain rebuild?"; then
                dkms remove "${nvidia_mod}/${nvidia_ver}" --all 2>/dev/null || true
                dkms install "${nvidia_mod}/${nvidia_ver}" -k "$running_k"
                return $?
            fi
        fi
        return 1
    else
        print_warn "DKMS status unrecognized: $dkms_status"
        print_warn "Check manually: dkms status"
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  Nouveau / Install / Main
# ══════════════════════════════════════════════════════════════════════════════

blacklist_nouveau(){
    local file="/etc/modprobe.d/blacklist-nouveau.conf"
    cat > "$file" <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
}

update_initramfs_if_available(){
    if command -v update-initramfs >/dev/null 2>&1; then
        # Target the running kernel explicitly.
        # Without -k, Debian updates the most recently *installed* kernel which may
        # be 7.0 even when the machine is booted into 6.12 — leaving 6.12 initramfs
        # without the nouveau blacklist and the nvidia module depmod entries.
        update-initramfs -u -k "$(uname -r)"
    fi
}

try_unload_nouveau(){
    if lsmod 2>/dev/null | grep -q '^nouveau\b'; then
        echo "Detected loaded nouveau module. Attempting to unload it (may fail if in use)..."
        modprobe -r nouveau 2>/dev/null || true
    fi
}

unblacklist_nouveau(){
    rm -f /etc/modprobe.d/blacklist-nouveau.conf
    update_initramfs_if_available
}

install_proprietary(){
    local codename="$1"
    local track="$2"
    local gpu_arch="$3"

    ensure_non_free_components

    blacklist_nouveau
    try_unload_nouveau

    # Smart driver selection — check both exit code AND output to guard against
    # any accidental stdout pollution that could slip into $pkg
    local pkg
    if ! pkg=$(find_best_nvidia_package "$codename" "$track" "$gpu_arch") || [[ -z $pkg ]]; then
        print_err "Cannot proceed: no compatible driver package found."
        unblacklist_nouveau
        return 1
    fi

    echo ""
    print_info "Installing: $pkg"
    echo ""

    # Determine if we should use backports source for installation
    local install_args=()
    if [[ -n $codename ]] && has_pkg_in_backports "$pkg" "$codename"; then
        print_info "Installing from ${codename}-backports..."
        install_args+=(-t "${codename}-backports")
    fi

    # Use exact headers for the running kernel (not linux-headers-amd64 which in
    # forky/testing points to 7.0 headers even when booted into a 6.12 kernel from stable)
    local running_k
    running_k=$(uname -r)
    local apt_ok=true
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${install_args[@]}" "$pkg" "linux-headers-${running_k}" firmware-misc-nonfree; then
        # dpkg errors here are usually caused by DKMS postinst failing to compile the
        # kernel module. The driver userspace libraries ARE installed. verify_dkms_build
        # will detect the broken state and attempt repair, so we continue rather than abort.
        print_warn "apt-get reported errors (likely DKMS postinst failure — see output above)."
        apt_ok=false
    fi

    update_initramfs_if_available

    # Post-install DKMS verification (detects "added"/"build-failed" and attempts repair)
    local dkms_ok=true
    if ! verify_dkms_build; then
        dkms_ok=false
    fi

    # Clean up bashium-managed backports if they were only needed for this install
    # and the track is testing (don't leave unnecessary backports)
    if [[ $track == "testing" ]] && has_bashium_backports; then
        echo ""
        if ask_question "Remove bashium-managed backports (no longer needed)?"; then
            disable_bashium_backports
        fi
    fi

    echo ""
    if [[ $dkms_ok == true ]]; then
        print_ok "NVIDIA proprietary driver installation complete. Reboot is recommended."
        if [[ $apt_ok == false ]]; then
            # apt-get failed because DKMS also tried to build for other installed kernels
            # (e.g. 7.0 headers still present on disk). That is expected and harmless —
            # what matters is that the module for the running kernel was built and installed.
            print_info "Note: apt reported errors because DKMS attempted to build for all"
            print_info "kernels with headers installed. Only the running kernel (${running_k}) matters."
            print_info "You can safely ignore those errors."
        fi
    else
        print_warn "Installation finished with errors — review messages above."
        print_warn "The NVIDIA kernel module was NOT installed for the running kernel."
        print_warn "Run this script again or reboot and retry."
    fi
}

configure_nouveau(){
    unblacklist_nouveau

    if ask_question "Remove proprietary NVIDIA packages if they are installed?"; then
        DEBIAN_FRONTEND=noninteractive apt-get purge -y 'nvidia-*' || true
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true
    fi

    # Clean up bashium backports if present
    if has_bashium_backports; then
        if ask_question "Remove bashium-managed backports?"; then
            disable_bashium_backports
        fi
    fi

    echo "Nouveau configuration complete. Reboot is recommended."
}

# ══════════════════════════════════════════════════════════════════════════════
#  Compatibility Logic for Pascal & Kernel 7.0
# ══════════════════════════════════════════════════════════════════════════════

is_pascal_conflict(){
    local gpu_arch="$1"
    local kmaj
    kmaj=$(get_kernel_major)
    if [[ "$gpu_arch" == "pascal" ]] && (( kmaj >= 7 )); then
        return 0
    fi
    return 1
}

# Returns 0 (true) if the currently running kernel is a real-time (RT) kernel
is_rt_kernel(){
    uname -r | grep -qi '\-rt'
}

# Query apt for an available linux-image-6.12 package matching the requested flavor.
# $1: "rt"  — look for an RT-flavoured package (name contains -rt-)
#     "std" — look for a standard (non-RT) package
# Prints the package name, or nothing if not found.
find_612_kernel_pkg(){
    local flavor="$1"
    local all
    all=$(apt-cache search --names-only '^linux-image-6\.12' 2>/dev/null | awk '{print $1}')
    if [[ $flavor == "rt" ]]; then
        echo "$all" | grep -- '-rt-' | grep 'amd64' | grep -Ev 'dbg|unsigned|cloud' | head -n1
    else
        echo "$all" | grep -v -- '-rt-' | grep 'amd64' | grep -Ev 'dbg|unsigned|cloud' | head -n1
    fi
}

# Same as above but for linux-headers-6.12
find_612_headers_pkg(){
    local flavor="$1"
    local all
    all=$(apt-cache search --names-only '^linux-headers-6\.12' 2>/dev/null | awk '{print $1}')
    if [[ $flavor == "rt" ]]; then
        echo "$all" | grep -- '-rt-' | grep 'amd64' | grep -Ev 'dbg|unsigned|cloud' | head -n1
    else
        echo "$all" | grep -v -- '-rt-' | grep 'amd64' | grep -Ev 'dbg|unsigned|cloud' | head -n1
    fi
}

install_compat_kernel(){
    local track="$1"
    local stable_codename="trixie"
    local stable_list="/etc/apt/sources.list.d/debian-stable-kernel.list"
    local stable_pin="/etc/apt/preferences.d/debian-stable-kernel-pin"

    print_info "Pascal GPU + Kernel 7.0 conflict detected."
    print_info "Kernel 6.12 (LTS) is recommended for better compatibility."

    # Detect RT vs standard kernel
    local kernel_flavor="std"
    if is_rt_kernel; then
        kernel_flavor="rt"
        print_info "RT kernel detected — will search for the RT variant of 6.12."
    fi

    if ! ask_question "Would you like to install Kernel 6.12 from ${stable_codename} (stable)?"; then
        return 0
    fi

    # Remove stale repo file left by older versions of this script (different filename)
    local old_stable_list="/etc/apt/sources.list.d/debian-stable.list"
    if [[ -f $old_stable_list ]]; then
        print_info "Removing stale repo file from previous run: ${old_stable_list}"
        rm -f "$old_stable_list"
    fi

    # --- Add stable repo only if trixie is not already configured anywhere ---
    local repo_added=false
    if ! grep -rqs "deb.*debian\.org.*\btrixie\b" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        print_info "Adding ${stable_codename} (stable) repository..."
        echo "deb http://deb.debian.org/debian/ ${stable_codename} main contrib non-free non-free-firmware" > "$stable_list"
        repo_added=true
    else
        print_info "${stable_codename} repository already configured."
    fi

    # Write pin regardless — ensures low priority even if repo was pre-existing
    if [[ ! -f $stable_pin ]]; then
        cat > "$stable_pin" <<EOF
Package: *
Pin: release a=stable
Pin-Priority: 50
EOF
    fi

    [[ $repo_added == true ]] && apt_update

    # --- Discover actual kernel image package via apt-cache (no hardcoded names) ---
    # Headers are intentionally skipped here: they pull in build-time deps (gcc, pahole,
    # kbuild) that version-conflict with forky. After reboot on 6.12, install_proprietary
    # installs linux-headers-amd64 cleanly from the running kernel's matching repo.
    local kernel_pkg
    kernel_pkg=$(find_612_kernel_pkg "$kernel_flavor")

    if [[ -z $kernel_pkg ]]; then
        print_err "No linux-image-6.12 package found for flavor '${kernel_flavor}' in ${stable_codename}."
        print_info "Packages visible in configured repos matching linux-image-6.12:"
        apt-cache search --names-only '^linux-image-6\.12' 2>/dev/null \
            | awk '{print "  " $1}' >&2 || true
        if [[ $repo_added == true ]]; then
            rm -f "$stable_list" "$stable_pin"
        fi
        return 1
    fi

    print_info "Kernel package : ${kernel_pkg}"
    print_info "Headers        : will be installed after reboot by the NVIDIA setup."

    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -t "${stable_codename}" "${kernel_pkg}"; then
        print_err "Failed to install kernel package. See apt output above."
        return 1
    fi

    update_initramfs_if_available

    print_ok "Kernel 6.12 (${kernel_flavor}) installed: ${kernel_pkg}"
    print_warn "ACTION REQUIRED: Please REBOOT and select Kernel 6.12 in the GRUB menu."
    print_warn "After rebooting, run this NVIDIA script again to install drivers."
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════════════════

# Parse flags: --yes skips interactive prompts (used when called from install.sh)
auto_yes=false
for arg in "$@"; do
    case "$arg" in
        --yes|--auto) auto_yes=true ;;
    esac
done

if ! has_nvidia_gpu; then
    echo "No NVIDIA GPU detected (via lspci)."
    exit 0
fi

print_header

echo "NVIDIA GPU detected."
echo ""

# Gather system information
codename=$(get_codename)
track=$(get_debian_track)
gpu_arch=$(detect_gpu_arch)
kernel_ver=$(get_kernel_version)

backports_status="no"
nonfree_status="no"
contrib_status="no"
nonfree_fw_status="no"
if has_backports_enabled; then backports_status="yes"; fi
if has_nonfree_enabled; then nonfree_status="yes"; fi
if has_contrib_enabled; then contrib_status="yes"; fi
if has_nonfree_firmware_enabled; then nonfree_fw_status="yes"; fi

cat <<EOF
+----------------------+-------------------------------+
| System Info          | Value                         |
+----------------------+-------------------------------+
| Debian track         | $track
| Codename             | ${codename:-unknown}
| Kernel               | $kernel_ver ($(uname -r))
| GPU architecture     | $gpu_arch
| Backports enabled    | $backports_status
| Contrib enabled      | $contrib_status
| Non-free enabled     | $nonfree_status
| Non-free-firmware    | $nonfree_fw_status
+----------------------+-------------------------------+
EOF

# Show compatibility warnings early
max_branch=$(max_driver_branch_for_arch "$gpu_arch")
min_branch=$(min_driver_branch_for_kernel)

if is_pascal_conflict "$gpu_arch"; then
    install_compat_kernel "$track"
fi

if is_legacy_gpu "$gpu_arch"; then
    echo ""
    print_warn "Your GPU ($gpu_arch) is a LEGACY architecture."
    print_warn "Maximum supported driver branch: ${max_branch}.xx"
    if (( min_branch > max_branch )); then
        print_err "Your kernel ($kernel_ver) requires driver >= ${min_branch}.xx"
        print_err "NO COMPATIBLE DRIVER EXISTS for this GPU + kernel combination."
        print_err "Consider booting an older kernel."
    fi
fi

echo ""

if [[ $auto_yes == true ]]; then
    # Called from install.sh — go straight to proprietary install
    install_proprietary "$codename" "$track" "$gpu_arch"
elif ask_question "Use proprietary NVIDIA driver (recommended for performance)?"; then
    install_proprietary "$codename" "$track" "$gpu_arch"
else
    configure_nouveau
fi
