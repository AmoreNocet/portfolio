/*
  ВОРОНКА АКТИВАЦИИ: регистрация → онбординг → ключевая фича → триал → оплата

  Бизнес-цель: найти шаги с наибольшим дропом для приоритизации продуктовых задач.

  Используется: CTE, FILTER, оконные функции, ROUND
*/

-- Шаг 1: флаги достижения каждого этапа воронки на уровне пользователя
WITH user_funnel AS (
    SELECT
        u.user_id,
        u.registered_at::date                           AS cohort_date,
        u.country,
        -- этап 1: регистрация — все пользователи по определению
        1                                               AS step_registered,
        -- этап 2: завершение онбординга в первые 7 дней
        MAX(CASE
            WHEN e.event_type = 'onboarding_complete'
             AND e.created_at <= u.registered_at + INTERVAL '7 days'
            THEN 1 ELSE 0
        END)                                            AS step_onboarding,
        -- этап 3: использование ключевой фичи в первые 14 дней
        MAX(CASE
            WHEN e.event_type = 'feature_used'
             AND e.created_at <= u.registered_at + INTERVAL '14 days'
            THEN 1 ELSE 0
        END)                                            AS step_feature,
        -- этап 4: хотя бы один успешный платёж (триал/первая оплата)
        MAX(CASE
            WHEN p.status = 'success'
            THEN 1 ELSE 0
        END)                                            AS step_paid,
        -- этап 5: повторный платёж (retention монетизации)
        COUNT(CASE WHEN p.status = 'success' THEN 1 END) AS total_payments
    FROM users u
    LEFT JOIN events e  ON e.user_id = u.user_id
    LEFT JOIN payments p ON p.user_id = u.user_id
    WHERE u.registered_at >= CURRENT_DATE - INTERVAL '180 days'   -- последние 6 мес
    GROUP BY u.user_id, u.registered_at, u.country
),

-- Шаг 2: агрегация по воронке
funnel_agg AS (
    SELECT
        COUNT(*)                                        AS n_registered,
        SUM(step_onboarding)                            AS n_onboarding,
        SUM(step_feature)                               AS n_feature,
        SUM(step_paid)                                  AS n_paid,
        SUM(CASE WHEN total_payments >= 2 THEN 1 END)   AS n_repeat_paid
    FROM user_funnel
)

-- Итоговая воронка с конверсиями на каждом шаге
SELECT
    'Регистрация'        AS funnel_step,
    1                    AS step_order,
    n_registered         AS users,
    100.0                AS conv_from_prev_pct,
    ROUND(100.0 * n_registered / n_registered, 1) AS conv_from_top_pct
FROM funnel_agg

UNION ALL SELECT 'Онбординг завершён', 2, n_onboarding,
    ROUND(100.0 * n_onboarding / n_registered, 1),
    ROUND(100.0 * n_onboarding / n_registered, 1)
FROM funnel_agg

UNION ALL SELECT 'Ключевая фича', 3, n_feature,
    ROUND(100.0 * n_feature / NULLIF(n_onboarding, 0), 1),
    ROUND(100.0 * n_feature / n_registered, 1)
FROM funnel_agg

UNION ALL SELECT 'Первый платёж', 4, n_paid,
    ROUND(100.0 * n_paid / NULLIF(n_feature, 0), 1),
    ROUND(100.0 * n_paid / n_registered, 1)
FROM funnel_agg

UNION ALL SELECT 'Повторный платёж', 5, n_repeat_paid,
    ROUND(100.0 * n_repeat_paid / NULLIF(n_paid, 0), 1),
    ROUND(100.0 * n_repeat_paid / n_registered, 1)
FROM funnel_agg

ORDER BY step_order;


-- ── Дополнительно: воронка в разрезе страны (топ-5 по трафику) ──────────────
WITH user_funnel AS (
    SELECT
        u.user_id,
        u.country,
        MAX(CASE WHEN e.event_type = 'onboarding_complete' THEN 1 ELSE 0 END) AS step_onboarding,
        MAX(CASE WHEN e.event_type = 'feature_used'        THEN 1 ELSE 0 END) AS step_feature,
        MAX(CASE WHEN p.status = 'success'                 THEN 1 ELSE 0 END) AS step_paid
    FROM users u
    LEFT JOIN events   e ON e.user_id = u.user_id
    LEFT JOIN payments p ON p.user_id = u.user_id
    WHERE u.registered_at >= CURRENT_DATE - INTERVAL '180 days'
    GROUP BY u.user_id, u.country
),
country_top5 AS (
    SELECT country
    FROM user_funnel
    GROUP BY country
    ORDER BY COUNT(*) DESC
    LIMIT 5
)
SELECT
    f.country,
    COUNT(*)                                                  AS n_users,
    ROUND(100.0 * SUM(step_onboarding) / COUNT(*), 1)        AS onboarding_pct,
    ROUND(100.0 * SUM(step_feature)    / COUNT(*), 1)        AS feature_pct,
    ROUND(100.0 * SUM(step_paid)       / COUNT(*), 1)        AS paid_pct
FROM user_funnel f
JOIN country_top5 c USING (country)
GROUP BY f.country
ORDER BY n_users DESC;