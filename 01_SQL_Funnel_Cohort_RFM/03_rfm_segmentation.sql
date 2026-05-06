/*
  RFM-СЕГМЕНТАЦИЯ КЛИЕНТСКОЙ БАЗЫ

  Бизнес-цель: выделить сегменты пользователей по ценности для CRM-кампаний,
  win-back и up-sell стратегий.

  RFM:
    R (Recency)   — сколько дней прошло с последней оплаты (меньше = лучше)
    F (Frequency) — количество оплат за период (больше = лучше)
    M (Monetary)  — суммарная выручка (больше = лучше)

  Метод: квантильная разбивка 1–4 по каждой оси, затем именование сегментов.
*/

-- Шаг 1: RFM-метрики на уровне пользователя
WITH rfm_raw AS (
    SELECT
        user_id,
        CURRENT_DATE - MAX(paid_at)::date              AS recency_days,
        COUNT(*)                                        AS frequency,
        SUM(amount)                                     AS monetary
    FROM payments
    WHERE status = 'success'
      AND paid_at >= CURRENT_DATE - INTERVAL '365 days'
    GROUP BY user_id
),

-- Шаг 2: квантили (оценки 1–4; для R инвертируем: меньше дней = выше балл)
rfm_scores AS (
    SELECT
        user_id,
        recency_days,
        frequency,
        monetary,
        NTILE(4) OVER (ORDER BY recency_days DESC)  AS r_score,  -- DESC: меньше дней → 4 (лучший)
        NTILE(4) OVER (ORDER BY frequency ASC)      AS f_score,
        NTILE(4) OVER (ORDER BY monetary ASC)       AS m_score
    FROM rfm_raw
),

-- Шаг 3: именование сегментов на основе RFM-профиля
rfm_segments AS (
    SELECT
        user_id,
        recency_days,
        frequency,
        ROUND(monetary::numeric, 2)                 AS monetary,
        r_score,
        f_score,
        m_score,
        r_score + f_score + m_score                 AS rfm_total,
        CASE
            WHEN r_score = 4 AND f_score >= 3                       THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3                      THEN 'Loyal Customers'
            WHEN r_score >= 3 AND f_score <= 2 AND m_score >= 3     THEN 'Potential Loyalists'
            WHEN r_score >= 3 AND f_score = 1                       THEN 'Recent Customers'
            WHEN r_score = 2 AND f_score >= 3 AND m_score >= 3      THEN 'At Risk'
            WHEN r_score = 2 AND f_score <= 2                       THEN 'Customers Needing Attention'
            WHEN r_score = 1 AND f_score >= 3                       THEN 'Cant Lose Them'
            WHEN r_score = 1 AND f_score <= 2 AND m_score >= 3      THEN 'Hibernating'
            ELSE 'Lost'
        END                                         AS segment
    FROM rfm_scores
)

-- Итог 1: распределение пользователей и выручки по сегментам
SELECT
    segment,
    COUNT(*)                                            AS user_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_users,
    ROUND(AVG(recency_days))                            AS avg_recency_days,
    ROUND(AVG(frequency), 1)                            AS avg_frequency,
    ROUND(AVG(monetary), 0)                             AS avg_monetary,
    ROUND(SUM(monetary), 0)                             AS total_revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue
FROM rfm_segments
GROUP BY segment
ORDER BY total_revenue DESC;


-- Итог 2: детализация для CRM-выгрузки (Champions + At Risk — приоритет работы)
SELECT
    s.user_id,
    u.country,
    s.segment,
    s.recency_days,
    s.frequency,
    s.monetary,
    s.rfm_total
FROM rfm_segments s
JOIN users u USING (user_id)
WHERE s.segment IN ('Champions', 'At Risk', 'Cant Lose Them')
ORDER BY s.segment, s.rfm_total DESC;
