# Agent framework - FAQ notes

## What is this agent framework

This tutorial's agent framework is a small set of Elixir modules for
building agents - LLMs that run in a loop, calling tools and reading their
results until a task is done. Its core logic is a few hundred lines. The
headline idea is that there are two ways an agent can act: by emitting a
structured tool call, or by writing and running a short program.

## ToolCallingAgent vs CodeAgent

ToolCallingAgent calls tools via structured JSON tool calls, one tool per
step. CodeAgent writes and evaluates a snippet of Elixir to call tools,
which lets it combine tool calls with loops, conditionals and variables in a
single step.

## Models

The framework talks to one model - Claude - directly over HTTP, with no
provider-abstraction layer in between. That keeps the request and response
shapes explicit and easy to read end to end.

## Tools

A tool needs a name, a description, typed inputs, and a function to run.
Tools can be built from a module (name/description/inputs/forward
callbacks) or from a plain function closure for tools that hold state, such
as a set of embedded documents. Tools can also be loaded from a remote MCP
server.

## Sandboxing

CodeAgent evaluates generated Elixir in the same process by default, guarded
by an allowlist of modules the code may call and a hard timeout. For
untrusted input, that evaluation should run in an isolated OS process or
container instead.

## Safety

Agents that browse the web can encounter prompt-injection attempts in page
content. Keep tools least-privileged, set a max step count, and do not give
an agent credentials it does not strictly need.
