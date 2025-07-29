#!/bin/bash
# Post-phase AI coordination hook

phase_name="$1"
phase_result="$2"
phase_duration="$3"

if [ "$AILINUX_AI_COORDINATION_ENABLED" = true ]; then
    ai_coordinate "phase_post_hook" "Post-phase analysis for $phase_name: $phase_result" "HookCoordinator" "info" "$phase_name"
    
    # Store phase results in AI memory
    store_ai_learning "phase_complete" "$phase_name" "$phase_result" "$phase_duration"
fi
