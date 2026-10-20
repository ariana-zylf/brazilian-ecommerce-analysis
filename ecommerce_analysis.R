# ==============================================================================
# PROJECT: Brazilian E-Commerce Analysis: Order Economics, Payment Behavior and Delivery SLA Performance
# PURPOSE: Quantitative Evaluation of Olist Marketplace Operations, Payment Mix, Freight Burdens, and Delivery SLA Variance
# AUTHOR:  Data Analyst Portfolio Case Study
# ==============================================================================

# 1. Load Required Libraries
library(tidyverse) # Includes ggplot2, dplyr, readr, tidyr
library(scales)    # For professional scale formatting in plots

# 2. Data Loading & Joining
orders   <- read_csv("olist_orders_dataset.csv")
payments <- read_csv("olist_order_payments_dataset.csv")
items    <- read_csv("olist_order_items_dataset.csv")

# Filter for delivered orders to analyze completed commercial performance
orders_clean <- orders %>% 
  filter(order_status == "delivered")

# Aggregate items to order level (summing price and freight)
items_aggregated <- items %>% 
  group_by(order_id) %>% 
  summarise(
    total_products_value = sum(price, na.rm = TRUE),
    total_freight_value  = sum(freight_value, na.rm = TRUE),
    total_items          = n()
  )

# Aggregate payments to order level (primary payment method and total payment)
payments_aggregated <- payments %>% 
  arrange(order_id, payment_sequential) %>%
  group_by(order_id) %>% 
  summarise(
    total_payment_value  = sum(payment_value, na.rm = TRUE),
    max_installments     = max(payment_installments, na.rm = TRUE),
    primary_payment_type = first(payment_type)
  )

# Master Dataset Join
df_master <- orders_clean %>% 
  inner_join(items_aggregated, by = "order_id") %>% 
  inner_join(payments_aggregated, by = "order_id") %>% 
  filter(primary_payment_type != "not_defined")

# ==============================================================================
# BLOCK 1: Revenue & Order Value Overview
# ==============================================================================

metrics_overview <- df_master %>% 
  summarise(
    total_revenue      = sum(total_payment_value, na.rm = TRUE),
    total_orders       = n_distinct(order_id),
    mean_aov   = mean(total_payment_value, na.rm = TRUE), # AOV
    median_aov = median(total_payment_value, na.rm = TRUE) # Median to handle skewness
  )

print("--- BLOCK 1: OVERVIEW METRICS ---")
print(metrics_overview)

# ==============================================================================
# BLOCK 2: Payment Methods & Installment Analysis
# ==============================================================================

payment_performance <- df_master %>% 
  group_by(primary_payment_type) %>% 
  summarise(
    total_orders   = n(),
    total_revenue = sum(total_payment_value, na.rm = TRUE),
    mean_aov      = mean(total_payment_value, na.rm = TRUE),
    mean_installments = mean(max_installments, na.rm = TRUE)
  ) %>% 
  mutate(
    order_share   = total_orders / sum(total_orders),
    revenue_share = total_revenue / sum(total_revenue)
  ) %>% 
  arrange(desc(total_revenue))

print("--- BLOCK 2: PAYMENT PERFORMANCE ---")
print(payment_performance)

# ==============================================================================
# BLOCK 3: Freight Burden Analysis (Commercial Economics)
# ==============================================================================

df_master_v1 <- df_master %>% 
  mutate(
    freight_ratio = total_freight_value / (total_products_value + total_freight_value)
  )

freight_summary <- df_master_v1 %>% 
  summarise(
    mean_products_value = mean(total_products_value, na.rm = TRUE),
    mean_freight_value  = mean(total_freight_value, na.rm = TRUE),
    overall_freight_ratio = mean(freight_ratio, na.rm = TRUE)
  )

print("--- BLOCK 3: FREIGHT RATIO OVERVIEW ---")
print(freight_summary)

# ==============================================================================
# BLOCK 4: Advanced Delivery SLA Performance logic
# ==============================================================================

df_delivery <- df_master %>% 
  drop_na(order_delivered_customer_date, order_estimated_delivery_date) %>% 
  mutate(
    delivery_delay_days = as.numeric(difftime(order_delivered_customer_date, order_estimated_delivery_date, units = "days")),
    sla_status = case_when(
      delivery_delay_days < -2 ~ "Delivered Early (>2 days ahead)",
      delivery_delay_days >= -2 & delivery_delay_days <= 0 ~ "On-Time (-2 to 0 days)",
      delivery_delay_days > 0 ~ "Delayed"
    )
  )

print("--- BLOCK 4: DELIVERY SLA OVERVIEW ---")
print(df_delivery)

# ==============================================================================
# BLOCK 5: Visualizations
# ==============================================================================

# Plot 1: Revenue Share vs Order Share by Payment Method
p1 <- payment_performance %>% 
  select(primary_payment_type, order_share, revenue_share) %>% 
  pivot_longer(cols = c(order_share, revenue_share), names_to = "metric", values_to = "percentage") %>% 
  ggplot(mapping=aes(x = reorder(primary_payment_type, -percentage), y = percentage, fill = metric)) +
  geom_col(position = "dodge", width = 0.6) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_fill_manual(
    values = c("order_share" = "#4A90E2", "revenue_share" = "#1B365D"),
    labels = c("Order Share", "Revenue Share")
  ) +
  labs(
    title = "Payment Performance: Order Share vs Revenue Share",
    subtitle = "Volume vs revenue yield across payment types",
    x = "Payment Type",
    y = "Percentage",
    fill = "Metric"
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())

# Plot 2: Distribution of Installments for Credit Card Transactions
p2 <- df_master %>% 
  filter(primary_payment_type == "credit_card", max_installments > 0) %>% 
  ggplot(mapping = aes(x = factor(max_installments))) +
  geom_bar(fill = "#1B365D", alpha = 0.85) +
  labs(
    title = "Distribution of Credit Card Installments",
    subtitle = "Customer payment structure preferences",
    x = "Number of Installments",
    y = "Total Orders"
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())

# Plot 3: Order Value vs Freight Burden Ratio
p3 <- df_master_v1 %>% 
  filter(total_products_value <= 500) %>% # Focus on typical transactions
  ggplot(mapping = aes(x = total_products_value, y = freight_ratio)) +
  geom_point(alpha = 0.1, color = "#4A90E2") +
  geom_smooth(method = "gam", color = "#D9534F", se = FALSE) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_x_continuous(labels = dollar_format(prefix = "R$ ")) +
  labs(
    title = "Freight Burden Ratio vs. Product Order Value",
    subtitle = "Higher freight impact on smaller orders",
    x = "Total Product Value (R$)",
    y = "Freight Burden Ratio" 
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())

# Plot 4: Refined SLA Performance
p4 <- df_delivery %>% 
  filter(delivery_delay_days >= -30 & delivery_delay_days <= 15) %>% 
  ggplot(mapping=aes(x = delivery_delay_days, fill = sla_status)) +
  geom_histogram(binwidth = 1, color = "white", alpha = 0.85) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black", linewidth = 1) +
  scale_fill_manual(
    values = c(
      "Delivered Early (>2 days ahead)" = "#3498DB", 
      "On-Time (-2 to 0 days)" = "#2ECC71",
      "Delayed" = "#E74C3C"
    )
  ) +
  labs(
    title = "Delivery SLA Performance: Promised vs Actual Delivery",
    subtitle = "Massive shift towards early deliveries",
    x = "Days Difference",
    y = "Total Orders",
    fill = "SLA Status"
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank())
 
# Render and Save Plots

print(p1)
ggsave("images/payment_performance.png", plot = p1, width = 8, height = 5, dpi = 300)
print(p2)
ggsave("images/installment_distribution.png", plot = p2, width = 8, height = 5, dpi = 300)
print(p3)
ggsave("images/freight_burden.png", plot = p3, width = 8, height = 5, dpi = 300)
print(p4)
ggsave("images/delivery_sla.png", plot = p4, width = 8, height = 5, dpi = 300)















