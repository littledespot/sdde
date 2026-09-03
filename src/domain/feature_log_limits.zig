pub const schema_version = "feature-log/v2";
pub const event_column_schema_id = "event-columns/v2";
pub const prompt_column_schema_id = "prompt-columns/v2";
pub const event_registry_id = "feature-log-events/poc-v2";
pub const redaction_policy_id = "redaction/default-v1";

pub const max_record_bytes: usize = 65_536;
pub const max_segment_bytes: usize = 8_388_608;
pub const max_segments: u8 = 16;
pub const retention_days: u8 = 14;
pub const retention_period_ms: u64 = @as(u64, retention_days) * 24 * 60 * 60 * 1000;
pub const lower_level_flush_records: u8 = 32;
pub const lower_level_flush_interval_ms: u16 = 1000;
pub const max_prompt_content_bytes: usize = 5000;
pub const stream_lock_deadline_ms: u16 = 2000;
pub const stream_lock_attempt_count: u8 = 1;
pub const emergency_max_ascii_bytes: usize = 128;
