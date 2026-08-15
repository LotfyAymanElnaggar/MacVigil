# Use Cases

MacVigil is useful whenever a Mac must keep doing work after the user stops interacting with it.

## AI and agentic development

- coding agents implementing features
- automated test/fix loops
- repository analysis and refactoring
- code review agents
- documentation generation
- browser/tool-use agents
- local MCP servers
- embedding and indexing jobs
- evaluation suites

The ideal future workflow is job-aware: MacVigil starts with the agent/process and releases protection when that process is done.

## Local AI

- Ollama
- LM Studio
- llama.cpp
- MLX runtimes
- local inference APIs
- model downloads
- model conversion and quantization
- batch inference
- local image/audio/video generation
- speech-to-text and text-to-speech
- RAG indexing and vector databases

## Software development

- Xcode and Swift builds
- Rust/C/C++ compilation
- Node package installs and builds
- Python pipelines
- Android builds
- long test suites
- end-to-end tests
- database migrations
- dependency updates
- monorepo tasks
- static analysis
- Git clones and Git LFS

## Dev servers and containers

- Next.js / Node
- Rails
- Django / Flask / FastAPI
- PostgreSQL / MySQL
- Redis
- Elasticsearch
- Docker / Docker Compose
- local Kubernetes
- webhook listeners
- local APIs

Future MacVigil triggers are planned around processes, ports, and containers rather than only timers.

## Remote development and access

- SSH
- Tailscale
- VPN-connected development
- macOS Screen Sharing
- remote desktop tools
- remote terminals
- local services exposed through secure tunnels

A remote Mac is only useful while it remains reachable.

## Downloads, uploads, and synchronization

- AI model files
- game/software downloads
- cloud-drive sync
- NAS copies
- `rsync`
- `scp` / SFTP
- browser downloads
- dataset transfers
- large media uploads

## Backups and storage work

- Time Machine
- NAS backups
- disk cloning
- archive generation
- external-drive copies
- cloud backup
- restore/migration jobs

## Creative workloads

### Video

- rendering
- transcoding
- exports
- proxy generation
- stabilization
- batch encoding

### 3D / CAD

- Blender renders
- simulations
- texture baking
- animation exports
- CAD rendering

### Photography

- RAW conversion
- Lightroom exports
- AI denoise
- panoramas
- batch resizing

### Audio

- long exports
- stems
- mastering/render passes
- podcast processing

## Data science and research

- Jupyter notebooks
- Python/R analyses
- MATLAB
- simulations
- optimization
- ETL pipelines
- data cleaning
- bioinformatics
- large dataset conversion
- model training/evaluation

## Self-hosting and home labs

- local web services
- dashboards
- media tooling
- databases
- automation services
- bots
- private APIs
- local AI endpoints
- CI/build runners

## Presentations, demos, kiosks, monitoring

These are the main **Full Awake** cases because the display itself is part of the job:

- presentations
- dashboards
- product demos
- booths
- classroom demonstrations
- monitoring screens
- installations

## Recording and streaming

- OBS
- screen recording
- audio capture
- podcasts
- webinars
- livestreaming
- camera capture

## Hardware/device workflows

- external SSD operations
- cameras
- microcontrollers
- development boards
- serial devices
- 3D-printer workflows
- data acquisition hardware
- long firmware/test runs

A future device-presence trigger could keep Vigil active only while a selected device is connected.

## Choosing a profile

Use **Compute Guard** when the job needs compute/network but not the screen.

Use **Closed-Lid Eco** only when you intentionally need a MacBook to continue running while closed, the model/OS combination is known to work, and the computer has safe ventilation.

Use **Full Awake** when the display must remain visible.
