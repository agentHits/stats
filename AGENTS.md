# Project Rules

## Non-Invasive Monitoring

- Stats/AgentHits is a passive macOS system monitor. Runtime monitoring features must observe system information and render it in the UI; they must not create avoidable side effects on the MacBook being monitored.
- Do not add steady-state disk persistence for monitoring data by default. Runtime histories for CPU, RAM, Disk, Network, Battery, Sensors, or similar metrics must be in-memory, bounded, and allowed to reset after app restart unless the user explicitly asks for durable storage.
- Do not add background JSON/log/cache/database/temp files, periodic file writes, file-backed metric histories, or save-on-terminate behavior for monitoring features without explicit approval and a documented overhead check.
- Do not add unnecessary periodic disk reads, process spawning, shell commands, network calls, indexing, scans, or high-frequency timers for monitoring features. Prefer existing in-process readers, read-only OS APIs, and bounded in-memory aggregation.
- Monitoring code must not materially affect the metrics it reports. In particular, Disk monitoring must not make Stats/AgentHits a noticeable disk reader/writer, and performance features must not become a visible CPU, memory, energy, or I/O source.
- Before completing any monitoring feature or bugfix, perform a self-impact check: list any new disk I/O, persistence, process spawning, network access, timer frequency, and memory growth; remove unnecessary impact; add tests or static searches when practical.
- If durable storage or heavier collection is truly required, pause and get explicit user approval first. Document what is stored, where it is stored, write/read frequency, retention, upper bounds, and verification that the overhead is negligible.
