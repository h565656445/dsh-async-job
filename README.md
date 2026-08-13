# dsh-async-job

<!-- DeepSeek Harness 衍生声明 -->
> **DeepSeek Harness 个人适配声明（Personal Adaptation Notice）**
>
> 本项目是 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的**个人适配产物（personal adaptation）**，**并非 DeepSeek Harness 官方文件（not an official DeepSeek Harness file）**，随附功能、使用说明与个人产物（bundled with features, documentation, and personal artifacts），可与 DeepSeek Harness 搭配使用，也可独立使用。
>
> This project is a **personal adaptation** for DeepSeek Harness, and is **NOT an official DeepSeek Harness file**, bundled with features, documentation, and personal artifacts. It can be used alongside DeepSeek Harness or standalone.

**作者 / Author**: [h565656445](https://github.com/h565656445)

**合作 / Collaboration**: 如有项目可以一起合作，欢迎联系。微信：`wohaishihenshuaide`。If you have projects, let's collaborate. WeChat: `wohaishihenshuaide`.


---

## 用途 / What this is for

异步任务协议：后台任务与回执，支持异步作业事件、意图与执行结果的类型化登记。

Async job protocol: background tasks and receipts with typed async-job events, intents and results.

---
## Hermes Async Job Protocol / Hermes 异步任务协议

本仓库实现 Hermes 异步任务协议：`HermesAsyncJob.psm1` 以 schema 注册表 v0.2 的 `async-job-intent` / `async-job-event` 为契约，维护 intent、只追加 Ledger 事件流与最终结果投影；`async_job_protocol.ps1` 提供 Prepare / Submit / Observe / Reconcile / Inspect 五个命令行 Action。

This repository implements the Hermes async job protocol: `HermesAsyncJob.psm1` is bound to the v0.2 `async-job-intent` / `async-job-event` schemas and maintains the intent, an append-only Ledger event stream, and the final result projection; `async_job_protocol.ps1` exposes five CLI Actions: Prepare / Submit / Observe / Reconcile / Inspect.

## Features / 功能

- 五阶段生命周期：Prepare / Submit / Observe / Reconcile / Inspect / Five-phase lifecycle (Prepare/Submit/Observe/Reconcile/Inspect)
- Schema 契约：intent 与 event 双 schema，SHA-256 身份绑定 / Schema-bound intent/event pair with SHA-256 identity
- 幂等追加：基于 Ledger 的只追加事件流 / Idempotent append-only Ledger event stream
- 状态推导：从事件流推导 pending→running→succeeded/failed / State derived from the event stream
- CLI 协议：`async_job_protocol.ps1` 直接可调用 / Callable CLI protocol

## What's inside / 目录结构

```
dsh-async-job/
├── README.md
├── LICENSE
├── src/HermesAsyncJob.psm1
├── runner/async_job_protocol.ps1
├── schemas/schema_registry/v0.2/
│   ├── async-job-intent.schema.json
│   └── async-job-event.schema.json
└── .dsh/
```

## Quick start / 快速开始

```powershell
# Prepare：登记任务意图
pwsh -NoProfile -File .\runner\async_job_protocol.ps1 -Action Prepare -RuntimeRoot .\runtime `
  -TaskId task-001 -ContractSha256 <sha256> -AdapterId my-adapter `
  -ProviderId deepseek -RequestSha256 <sha256> -BudgetCny 1.0

# Observe：回报提供方观测
pwsh -NoProfile -File .\runner\async_job_protocol.ps1 -Action Observe -RuntimeRoot .\runtime `
  -TaskId task-001 -JobPath .\job.json -ProviderJobRef ref-1 `
  -ObservedProviderId deepseek -ObservedIntentSha256 <sha256> -ObservedContractSha256 <sha256>
```

## DeepSeek Harness 衍生 / DSH Derivative

本项目附带 DeepSeek Harness 衍生包，位于 `.dsh/` 目录：

- `preset.yml` — Agent 预设元数据
- `agent.cordis.yml` — Cordis 组装（基于 standard 预设，persona 已定制）
- `skills/dsh-async-job/SKILL.md` — 项目专属技能（skill）

安装与接入方式见 [`.dsh/README.md`](.dsh/README.md)（双语）。

## License / 许可证

[MIT](LICENSE)

---

## 相关项目 / Related Projects

> 这是 DeepSeek Harness 个人适配系列（共 40 个仓库）的完整导航。 / This is the complete navigation for the DeepSeek Harness personal-adaptation series (40 repos).

### Agent OS 内核 / Kernel

[`dsh-agent-os-runtime`](https://github.com/h565656445/dsh-agent-os-runtime) · [`dsh-agent-os-planning`](https://github.com/h565656445/dsh-agent-os-planning) · [`dsh-agent-os-scheduler`](https://github.com/h565656445/dsh-agent-os-scheduler) · [`dsh-agent-os-worker-protocol`](https://github.com/h565656445/dsh-agent-os-worker-protocol) · [`dsh-agent-os-observability`](https://github.com/h565656445/dsh-agent-os-observability) · [`dsh-agent-os-specs`](https://github.com/h565656445/dsh-agent-os-specs)

### Harness 基础设施 / Infrastructure

[`dsh-harness-core`](https://github.com/h565656445/dsh-harness-core) · [`dsh-graph-entry`](https://github.com/h565656445/dsh-graph-entry) · **`dsh-async-job`（本仓库 / this repo）** · [`dsh-file-identity`](https://github.com/h565656445/dsh-file-identity) · [`dsh-json-projection`](https://github.com/h565656445/dsh-json-projection) · [`dsh-manual-approval`](https://github.com/h565656445/dsh-manual-approval) · [`dsh-observation-writer`](https://github.com/h565656445/dsh-observation-writer) · [`dsh-provider-control`](https://github.com/h565656445/dsh-provider-control) · [`dsh-schema-negotiator`](https://github.com/h565656445/dsh-schema-negotiator) · [`dsh-schema-registry`](https://github.com/h565656445/dsh-schema-registry) · [`dsh-upgrade-governance`](https://github.com/h565656445/dsh-upgrade-governance) · [`dsh-task-contract`](https://github.com/h565656445/dsh-task-contract) · [`dsh-quality-gates`](https://github.com/h565656445/dsh-quality-gates) · [`dsh-worker-tests`](https://github.com/h565656445/dsh-worker-tests)

### Worker 与管线 / Workers & Pipelines

[`dsh-codex-worker`](https://github.com/h565656445/dsh-codex-worker) · [`dsh-novel-chapter-trial`](https://github.com/h565656445/dsh-novel-chapter-trial) · [`dsh-novel-video-pipeline`](https://github.com/h565656445/dsh-novel-video-pipeline) · [`dsh-portfolio-routing`](https://github.com/h565656445/dsh-portfolio-routing) · [`dsh-meta-agents-bridge`](https://github.com/h565656445/dsh-meta-agents-bridge)

### 规格与文档 / Specs & Docs

[`dsh-harness-specs`](https://github.com/h565656445/dsh-harness-specs) · [`dsh-novel-specs`](https://github.com/h565656445/dsh-novel-specs) · [`dsh-architecture-guide`](https://github.com/h565656445/dsh-architecture-guide) · [`dsh-powershell-patterns`](https://github.com/h565656445/dsh-powershell-patterns) · [`dsh-json-schema-driven-dev`](https://github.com/h565656445/dsh-json-schema-driven-dev) · [`dsh-llm-agent-harness-guide`](https://github.com/h565656445/dsh-llm-agent-harness-guide)

### 适配器 / Adapters

[`dsh-short-story-engine`](https://github.com/h565656445/dsh-short-story-engine) · [`dsh-tutorial-video-state-machine`](https://github.com/h565656445/dsh-tutorial-video-state-machine) · [`dsh-governance-kernel`](https://github.com/h565656445/dsh-governance-kernel) · [`dsh-sports-pipeline`](https://github.com/h565656445/dsh-sports-pipeline) · [`dsh-motion-grammar`](https://github.com/h565656445/dsh-motion-grammar)

### DSH 总集成 / Integration

[`dsh-integration`](https://github.com/h565656445/dsh-integration) · [`dsh-presets-pack`](https://github.com/h565656445/dsh-presets-pack) · [`dsh-skills-pack`](https://github.com/h565656445/dsh-skills-pack) · [`dsh-starter-kit`](https://github.com/h565656445/dsh-starter-kit)

