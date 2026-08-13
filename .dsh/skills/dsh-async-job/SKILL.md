---
name: dsh-async-job
description: Hermes 异步任务协议五阶段生命周期与意图/事件契约技能 / Skill for the Hermes async job protocol: five-phase lifecycle and intent/event contracts
---

# Hermes 异步任务协议 / Hermes Async Job Protocol

本技能用于 Hermes 异步任务协议：按 Prepare/Submit/Observe/Reconcile/Inspect 五阶段推进任务，遵守 intent/event schema 契约与 Ledger 只追加语义。

This skill covers the Hermes async job protocol: driving jobs through Prepare/Submit/Observe/Reconcile/Inspect while honoring the intent/event schema contracts and the append-only Ledger semantics.

## When to use / 何时使用

需要登记、提交、观测、对账或检查异步任务时。

Use when preparing, submitting, observing, reconciling, or inspecting async jobs.

## Workflow / 工作流

1. Prepare 登记意图（async-job-intent）。
2. Submit 提交提供方。
3. Observe 回报观测（async-job-event）。
4. Reconcile / Inspect 对账与检查状态。

## References / 参考

- 项目 README: 见仓库根目录
- 作者: h565656445 (GitHub)