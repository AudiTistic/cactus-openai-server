# TODO: Pending Features

This document tracks features that need to be implemented for the Cactus OpenAI Server.

## Priority 1: UI Enhancements

### Power Management
- [ ] Add wakelock toggle switch (Keep Screen On)
  - Dependencies already added: `wakelock_plus`
  - Implement `_toggleWakeLock()` function
  - Add switch UI in power management card
- [ ] Display battery status and level
  - Dependencies already added: `battery_plus`
  - Show battery percentage
  - Show charging status
- [ ] Android Screen Pinning support
  - Add button to enable/guide user to pin app
  - Allows phone to be locked but app remains accessible

### Request Logging & Metrics
- [ ] Implement expandable log view
  - Show 2-line log entries for each request
  - Line 1: `/v1/<endpoint>                       Tokens: <input_tokens>`
  - Line 2: `TTG: <tokens_generated> | TTL: <time_to_last>s | TPS: <tokens_per_second> | PTS: <prompt_time>s`
  - Add horizontal divider between entries
  - Auto-scroll to bottom on new entries
  - Delete entries that scroll out of view
- [ ] Add metrics footer bar
  - Left side: `TPP: <total_prompts_processed>`
  - Right side: `QUE: <queued_requests>`
  - Always visible at bottom of log
- [ ] Add metrics legend/key at top
  - TTG = Tokens Generated
  - TPS = Tokens Per Second 
  - PTS = Prompt Timer Seconds
  - TTL = Time To Last (token)
- [ ] Add expand/collapse button for log
  - Collapsed: Shows last few entries
  - Expanded: Maximizes log to fill screen

## Priority 2: Request Queue Management

- [ ] Implement request queuing system
  - Queue incoming requests when model is busy
  - Process requests sequentially (FIFO)
  - Update `_queuedRequests` counter in realtime
  - Update `_activeRequests` counter
  - Increment `_totalPromptsProcessed` on completion

## Priority 3: Dynamic Token Limits

- [ ] Investigate CactusAI context length API
  - CactusAI currently has 2500 token limit in settings
  - Determine if nCtx or similar parameter exists
  - Check CactusLM initialization parameters
- [ ] Implement dynamic token limit based on device RAM
  - Use `device_info_plus` to get available memory
  - Calculate safe context size based on model size and available RAM
  - Mobile devices have unified memory architecture (better for LLMs than PC)
  - Set max_tokens intelligently:
    - Cap user requests to calculated limit
    - Provide UI slider/input for max context
    - Show available vs. used context
- [ ] Add UI controls for token management
  - Display current context limit
  - Allow manual override (with warnings)
  - Show memory usage estimates

## Technical Notes

### Dependencies Status
✅ `wakelock_plus` - Added to pubspec.yaml  
✅ `battery_plus` - Added to pubspec.yaml  
✅ `device_info_plus` - Added to pubspec.yaml  

### Implementation Strategy
1. Start with logging/metrics UI (most visible improvement)
2. Add queue management (improves stability)
3. Implement power management (user convenience)
4. Research and implement dynamic token limits (requires CactusAI API investigation)

### CactusAI API Research Needed
- Documentation: Check if CactusLM has context length parameters
- Source code: Review cactus package for nCtx, context_length, or similar
- Test: Try passing large max_tokens values to see behavior
- Alternative: If no API exists, document current 2500 limit clearly in UI

## Performance Targets
- Log updates: < 16ms (60fps)
- Queue processing: Immediate request acceptance, background execution
- Memory overhead: < 50MB for UI and logging
- Battery impact: Minimal when wakelock disabled

---

**Last Updated**: Auto-generated during development session  
**Status**: Ready for implementation
