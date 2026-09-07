//! Shared run-command policy for the reference agents (campaign R2).
//!
//! Replaces shell-string execution of message-derived
//! commands with an argv allowlist, strict validation, fail-closed LLM
//! confirmation, and an explicit operator-confirmation flag. Shell compounds
//! are rejected, never re-interpreted.

use serde_json::Value;

pub const ALLOWED_INTERPRETERS: [&str; 5] = ["python3", "python", "node", "npm", "npx"];
const MAX_ARGV_LENGTH: usize = 16;
const MAX_ARG_LENGTH: usize = 512;
const FORBIDDEN: &[char] = &[
    ';', '&', '|', '`', '$', '<', '>', '(', ')', '{', '}', '*', '"', '\'', '\n', '\r', '\\',
];

fn arg_is_safe(arg: &str) -> Result<(), String> {
    if arg.is_empty() {
        return Err("run command arguments must be non-empty strings".into());
    }
    if arg.len() > MAX_ARG_LENGTH {
        return Err(format!(
            "run command argument too long: {}…",
            &arg[..32.min(arg.len())]
        ));
    }
    if arg.contains(FORBIDDEN) {
        return Err(format!("run command argument contains forbidden characters: {arg:?}"));
    }
    if arg.starts_with('/') {
        return Err(format!("absolute paths are not allowed in run commands: {arg:?}"));
    }
    if arg == ".." || arg.starts_with("../") || arg.contains("/../") || arg.ends_with("/..") {
        return Err(format!("path traversal is not allowed in run commands: {arg:?}"));
    }
    Ok(())
}

/// Validate a full argv. Returns the validated argv or an explanation.
pub fn validate_run_argv(argv: &[String]) -> Result<Vec<String>, String> {
    if argv.is_empty() {
        return Err("run command must be a non-empty argv array".into());
    }
    if argv.len() > MAX_ARGV_LENGTH {
        return Err(format!("run command exceeds {MAX_ARGV_LENGTH} arguments"));
    }
    for arg in argv {
        arg_is_safe(arg)?;
    }
    let interpreter = &argv[0];
    if !ALLOWED_INTERPRETERS.contains(&interpreter.as_str()) {
        return Err(format!(
            "interpreter {interpreter:?} is not in the allowlist ({})",
            ALLOWED_INTERPRETERS.join(", ")
        ));
    }
    Ok(argv.to_vec())
}

/// Parse a legacy single-string command strictly. Shell compounds are
/// rejected (never re-interpreted).
pub fn parse_run_command(raw: &str) -> Result<Vec<String>, String> {
    let cmd = raw.trim();
    if cmd.is_empty() {
        return Err("run command is empty".into());
    }
    if cmd.contains(FORBIDDEN) {
        return Err("run command contains forbidden characters (shell compounds are rejected)".into());
    }
    let argv: Vec<String> = cmd.split_whitespace().map(String::from).collect();
    validate_run_argv(&argv)
}

pub fn validate_run_cmd_string(raw: &str) -> Result<Vec<String>, String> {
    parse_run_command(raw)
}

/// Resolve the confirmed argv for a run stage from `params`.
///
/// - `params.cmd_argv` (validated argv) is used as the operator-provided path.
/// - otherwise `params.cmd` is LLM-confirmed; any confirmation failure is
///   terminal (the raw suggestion is never executed).
/// - `params.confirm` must be exactly `true`.
///
/// Returns `Ok((argv, display))` or `Err(error_info_json)`.
pub fn resolve_run_stage(params: &Value) -> Result<(Vec<String>, Value), Value> {
    let confirm = params.get("confirm").and_then(|v| v.as_bool()).unwrap_or(false);
    if !confirm {
        return Err(serde_json::json!({"error": "run_not_confirmed"}));
    }
    if let Some(argv_value) = params.get("cmd_argv") {
        let parsed: Vec<String> = match serde_json::from_value(argv_value.clone()) {
            Ok(v) => v,
            Err(_) => {
                return Err(serde_json::json!({"error": "run command must be an array of strings"}));
            }
        };
        return match validate_run_argv(&parsed) {
            Ok(argv) => Ok((argv.clone(), serde_json::json!({"cmd": argv.join(" "), "argv": argv}))),
            Err(e) => Err(serde_json::json!({"error": e})),
        };
    }
    let suggested = params.get("cmd").and_then(|v| v.as_str()).unwrap_or("");
    if suggested.trim().is_empty() {
        return Err(serde_json::json!({"error": "no_run_command"}));
    }
    // LLM confirmation happens in the caller (async runtime); this function
    // validates the confirmed string.
    match validate_run_cmd_string(suggested) {
        Ok(argv) => {
            let display = serde_json::json!({"cmd": suggested, "argv": argv});
            Ok((argv, display))
        }
        Err(e) => Err(serde_json::json!({"error": e, "cmd": suggested})),
    }
}

pub fn confirmation_failed(cmd: &str) -> Value {
    serde_json::json!({"error": "llm_confirmation_unavailable", "cmd": cmd})
}
