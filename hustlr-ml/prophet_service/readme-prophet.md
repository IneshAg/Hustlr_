# Hustlr Prophet Disruption Forecasting

## Why Prophet for Disruption Forecasting?
Facebook Prophet is well-suited for disruption forecasting because it handles strong seasonal effects (such as the Chennai monsoon) very elegantly with customizable Fourier terms. Additionally, it easily models specific holidays, political events, or specific regressors like our custom `is_monsoon_season` flag, capturing the fact that heavy and extreme rain events are not uniformly distributed but are heavily focused in Oct-Dec.

## Wednesday Nudge Logic and Adverse Selection Protection
The wedge feature of Hustlr predicts disruptions and notifies workers on Wednesday ahead of the weekend. If a high-probability event (like Heavy Rain with >60% certainty) is detected, workers are nudged.

**Adverse Selection Protection:** If an uncovered worker gets a nudge, they *cannot* activate a plan to get paid for that exact forecasted event within the same week. The system mandates a quarterly commitment, and the nudge explicitly says: `"Coverage starts next Monday — activate quarterly plan now."` This locks out opportunistic buying while using the threat of the event as an educational conversion hook.

## Monsoon Surcharge Formula
A hard-coded actuarial protection: during October, November, and December, the base premium is automatically increased by an additional 22%. This is because the baseline risk probability of rain-triggered events rises from ~12% in the dry season to over 32% during the Chennai monsoon.
