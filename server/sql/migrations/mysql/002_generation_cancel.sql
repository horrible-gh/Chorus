-- Migration: 002_generation_cancel.sql (MySQL)
-- Purpose: Add generation tracking columns to tasks table,
--          create generation_cancel_log table, and related indexes.
-- Ref: DB005

-- -----------------------------------------------------------------------
-- 1. tasks 테이블 확장
-- -----------------------------------------------------------------------

ALTER TABLE `tasks` ADD COLUMN `generation_id` TEXT;
ALTER TABLE `tasks` ADD COLUMN `room_id` TEXT;
ALTER TABLE `tasks` ADD CONSTRAINT `fk_tasks_room_id` FOREIGN KEY (`room_id`) REFERENCES `chat_rooms`(`room_id`);
ALTER TABLE `tasks` ADD COLUMN `source_message_id` TEXT;
ALTER TABLE `tasks` ADD CONSTRAINT `fk_tasks_source_message_id` FOREIGN KEY (`source_message_id`) REFERENCES `messages`(`message_id`);
ALTER TABLE `tasks` ADD COLUMN `cancelled_at` TIMESTAMP NULL;
ALTER TABLE `tasks` ADD COLUMN `cancel_requested_at` TIMESTAMP NULL;

-- -----------------------------------------------------------------------
-- 2. generation_cancel_log 테이블 신설
-- -----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `generation_cancel_log` (
    `log_id` TEXT NOT NULL PRIMARY KEY,
    `generation_id` TEXT NOT NULL,
    `task_id` TEXT NOT NULL,
    `room_id` TEXT NOT NULL,
    `requested_by_user_id` TEXT,
    `request_source` TEXT NOT NULL,
    `result` TEXT NOT NULL,
    `result_detail` TEXT,
    `requested_at` TIMESTAMP NOT NULL,
    `processed_at` TIMESTAMP NULL,
    CONSTRAINT `fk_cancel_log_task_id` FOREIGN KEY (`task_id`) REFERENCES `tasks`(`task_id`),
    CONSTRAINT `chk_request_source` CHECK (`request_source` IN ('user_click', 'room_leave', 'system')),
    CONSTRAINT `chk_result` CHECK (`result` IN ('cancelled', 'already_completed', 'already_cancelled', 'already_failed', 'not_found', 'server_error'))
);

-- -----------------------------------------------------------------------
-- 3. 인덱스 생성
-- -----------------------------------------------------------------------

-- tasks 추가 인덱스
CREATE INDEX `idx_tasks_generation_id` ON `tasks`(`generation_id`);
CREATE INDEX `idx_tasks_room_status` ON `tasks`(`room_id`, `status`);

-- generation_cancel_log 인덱스
CREATE INDEX `idx_cancel_log_generation` ON `generation_cancel_log`(`generation_id`);
CREATE INDEX `idx_cancel_log_room` ON `generation_cancel_log`(`room_id`, `requested_at`);
CREATE INDEX `idx_cancel_log_user` ON `generation_cancel_log`(`requested_by_user_id`, `requested_at`);
