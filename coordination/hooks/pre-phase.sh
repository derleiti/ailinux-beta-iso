#!/bin/bash
# Pre-phase AI coordination hook

phase_name="$1"
phase_description="$2"

if [ "$AILINUX_AI_COORDINATION_ENABLED" = true ]; then
    ai_coordinate "phase_pre_hook" "Pre-phase validation for $phase_name" "HookCoordinator" "info" "$phase_name"
    
    # Store phase context in AI memory
    store_ai_context "phase_start" "$phase_name" "$phase_description"
fi
