# Customer 360 Analytics Pipeline — Snowflake Data Lake on AWS

<div align="center">

# 🏦 NorthBridge Customer 360 Analytics Platform

### Enterprise-Grade Cloud Data Engineering Project using AWS, Snowflake, Terraform & Streamlit

![Terraform](https://img.shields.io/badge/Terraform-IaC-blueviolet?style=for-the-badge\&logo=terraform)
![AWS](https://img.shields.io/badge/AWS-Cloud-orange?style=for-the-badge\&logo=amazonaws)
![Snowflake](https://img.shields.io/badge/Snowflake-Data%20Cloud-skyblue?style=for-the-badge\&logo=snowflake)
![Python](https://img.shields.io/badge/Python-3.10+-yellow?style=for-the-badge\&logo=python)
![Streamlit](https://img.shields.io/badge/Streamlit-Dashboard-red?style=for-the-badge\&logo=streamlit)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

</div>

---

# 📌 Project Overview

NorthBridge Bank is a fictional enterprise retail bank whose customer information is scattered across:

* Core banking systems
* Loan origination systems
* CRM platforms
* Credit systems
* Transaction processing services
* Compliance platforms

This project builds a **Customer 360 unified analytics platform** using:

* AWS Cloud Infrastructure
* Snowflake Data Lakehouse
* Terraform Infrastructure as Code
* Event-driven ingestion pipelines
* Streamlit analytics dashboards

The platform ingests:

* 25,000 customer records
* 300,000+ banking transactions
* Loan and account data
* AML/KYC compliance records
* Nested JSON datasets

and transforms them through a:

```text
BRONZE → SILVER → GOLD
```

medallion architecture pipeline.

---

# 🚀 Key Features

## ☁️ Cloud Infrastructure

* AWS S3 storage
* IAM role-based security
* Terraform-managed infrastructure
* Multi-environment deployments
* HCP Terraform remote state
* CI/CD GitHub workflows

---

## ❄️ Snowflake Data Platform

* Dynamic tables
* Snowpipe auto-ingestion
* Data lakehouse architecture
* Analytical views
* Role-based access control
* Multi-schema warehouse setup

---

## 📊 Analytics & Dashboarding

* Customer 360 insights
* Loan portfolio analysis
* Risk monitoring
* Transaction analytics
* AML/KYC compliance tracking
* Streamlit dashboards

---

## 🔐 Security & Governance

* Least-privilege IAM policies
* RSA key-pair authentication
* Secure Terraform secrets handling
* Environment isolation
* Remote state management

---

# 🏗️ System Architecture

## High-Level Architecture

```text
                ┌──────────────────┐
                │ Banking JSON Data│
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ AWS S3 Raw Bucket│
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ Snowpipe Ingest  │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ BRONZE Layer     │
                │ Raw JSON Storage │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ SILVER Layer     │
                │ Cleansed Data    │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ GOLD Layer       │
                │ Analytics Models │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ Streamlit App    │
                │ Customer 360 BI  │
                └──────────────────┘
```

---

# 🧠 Medallion Architecture

| Layer  | Purpose                                      |
| ------ | -------------------------------------------- |
| BRONZE | Raw ingestion of nested JSON banking data    |
| SILVER | Cleansed, typed, deduplicated datasets       |
| GOLD   | Curated analytical fact and dimension tables |

---

# 📂 Repository Structure

```text
customer360-snowflake-pipeline/
│
├── app/
│   └── northbridge_dashboard.py
│
├── data/
│   └── banking datasets
│
├── documentation/
│   └── architecture ppt
│
├── infra/platform/tf/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── modules/
│   ├── config/
│   ├── templates/
│   └── environments/
│
├── .github/workflows/
│   ├── ci.yaml
│   ├── terraform-deploy.yaml
│   ├── terraform-destroy.yaml
│   └── deploy-streamlit-app.yaml
│
├── .claude/skills/
├── CHANGELOG.md
├── CONTRIBUTING.md
├── README.md
└── LICENSE
```

---

# 🛠️ Tech Stack

| Category        | Technologies   |
| --------------- | -------------- |
| Cloud           | AWS            |
| IaC             | Terraform      |
| Data Warehouse  | Snowflake      |
| Programming     | Python         |
| Dashboard       | Streamlit      |
| CI/CD           | GitHub Actions |
| Security        | IAM, RSA Keys  |
| Storage         | Amazon S3      |
| Version Control | Git & GitHub   |

---

# 📋 Prerequisites

Before starting, install:

## Required Software

| Tool      | Version |
| --------- | ------- |
| Terraform | >= 1.14 |
| Python    | >= 3.10 |
| AWS CLI   | Latest  |
| Git       | Latest  |
| OpenSSL   | Latest  |

---

# ☁️ Required Accounts

You need:

* AWS Account
* Snowflake Trial/Enterprise Account
* HCP Terraform Account
* GitHub Account

---

# ⚡ Quick Start Guide

# 1️⃣ Clone Repository

```bash
git clone <repository-url>
cd aws-csv-data-pipeline
```

---

# 2️⃣ Generate RSA Keypair

```bash
mkdir -p infra/platform/keypair
cd infra/platform/keypair

openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_key.p8 -nocrypt

openssl rsa -in snowflake_key.p8 -pubout -out snowflake_key.pub
```

---

# 3️⃣ Configure Snowflake User

Create:

* Service User
* Provisioner Roles
* Analyst Roles
* Warehouse Permissions

Use:

```sql
CREATE USER GITHUB_ACTIONS_USER;
```

and assign required privileges.

---

# 4️⃣ Configure HCP Terraform Variables

Create:

## Variable Sets

### Snowflake Credentials

* snowflake_private_key
* TF_VAR_snowflake_account_name
* TF_VAR_snowflake_user

### AWS Credentials

* AWS_ACCESS_KEY_ID
* AWS_SECRET_ACCESS_KEY

---

# 5️⃣ Initialize Terraform

```bash
cd infra/platform/tf

terraform init
terraform validate
terraform fmt -recursive
```

---

# 6️⃣ Deploy Infrastructure

## Pass A

```bash
terraform apply -var-file="terraform.tfvars" -var="enable_snowpipe_creation=false"
```

## Pass B

```bash
terraform apply -var-file="terraform.tfvars"
```

---

# 7️⃣ Upload Dataset

```bash
aws s3 cp data/ s3://northbridge-raw-data/raw-data/json/ --recursive --include "*.json"
```

---

# 8️⃣ Verify Pipeline

```sql
SELECT COUNT(*) FROM NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE;
```

Expected:

```text
25000
```

---

# 📊 Streamlit Dashboard

The dashboard includes:

## Executive KPIs

* AUM Metrics
* NPL Ratio
* Credit Scores
* Regional Revenue

---

## Customer Insights

* Income distributions
* Segment analysis
* Customer demographics

---

## Loan Portfolio

* Loan risk
* Loan amount analysis
* EMI analytics
* Delinquency monitoring

---

## Transactions Analytics

* Monthly transaction trends
* Channel usage
* Failed transaction analysis

---

## Risk & Compliance

* AML exposure
* KYC verification
* Risk scoring
* Fraud indicators

---

# 🔐 Security Architecture

## IAM Principles Used

* Least privilege access
* Role-based security
* Environment isolation
* Secure CI/CD authentication

---

## RSA Key Authentication

Snowflake authentication uses:

* JWT-based authentication
* RSA keypair security
* Passwordless CI/CD deployments

---

# 🧩 Terraform Modules

| Module               | Purpose                        |
| -------------------- | ------------------------------ |
| database_schemas     | Creates databases and schemas  |
| warehouse            | Creates Snowflake warehouses   |
| table                | Creates analytical tables      |
| dynamic_table        | Creates dynamic refresh tables |
| storage_integrations | Configures AWS integrations    |
| pipe                 | Creates Snowpipe ingestion     |

---

# 📈 Data Statistics

| Metric       | Value     |
| ------------ | --------- |
| Customers    | 25,000    |
| Transactions | ~312,000  |
| Loans        | ~35,000   |
| Accounts     | ~75,000   |
| Dataset Size | ~329 MB   |
| Date Range   | 2022–2024 |

---

# 📚 Domain Glossary

| Term | Meaning                     |
| ---- | --------------------------- |
| AUM  | Assets Under Management     |
| AML  | Anti-Money Laundering       |
| KYC  | Know Your Customer          |
| NPL  | Non-Performing Loan         |
| PEP  | Politically Exposed Person  |
| EMI  | Equated Monthly Installment |

---

# 🔄 CI/CD Workflows

## GitHub Actions Included

| Workflow                  | Purpose                   |
| ------------------------- | ------------------------- |
| ci.yaml                   | Validation & formatting   |
| terraform-deploy.yaml     | Infrastructure deployment |
| terraform-destroy.yaml    | Infrastructure teardown   |
| deploy-streamlit-app.yaml | Dashboard deployment      |

---

# 🧪 Validation Queries

## Check Raw Ingestion

```sql
SELECT COUNT(*)
FROM NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE;
```

---

## Check SILVER Layer

```sql
SELECT COUNT(*)
FROM NORTHBRIDGE_DATABASE.SILVER.CLEAN_NORTHBRIDGE_DT;
```

---

## Check GOLD Layer

```sql
SELECT COUNT(*)
FROM NORTHBRIDGE_DATABASE.GOLD.FACT_TRANSACTIONS;
```

---

# 🧯 Common Errors & Fixes

## Terraform Init Failure

### Cause

Provider version mismatch.

### Fix

```bash
terraform init -upgrade
```

---

## Snowflake Authentication Failure

### Cause

Incorrect private key encoding.

### Fix

Re-generate RSA keypair correctly.

---

## AWS Permission Denied

### Cause

IAM role lacks permissions.

### Fix

Review:

* IAM policies
* S3 bucket permissions
* Trust relationships

---

# 🧑‍💻 Contributing Guide

We welcome contributions from:

* Cloud engineers
* Terraform developers
* Data engineers
* DevOps learners
* Open-source contributors

---

# 🚀 Contribution Workflow

## Fork Repository

```bash
git fork
```

---

## Create Branch

```bash
git checkout -b feature/new-feature
```

---

## Commit Changes

```bash
git commit -m "docs: improve README"
```

---

## Push Changes

```bash
git push origin feature/new-feature
```

---

## Create Pull Request

Open a PR with:

* Clear description
* Screenshots if applicable
* Issue references
* Testing evidence

---

# 🎯 Beginner Contribution Ideas

## Documentation

* Improve setup instructions
* Add screenshots
* Add architecture explanations
* Fix typos
* Add troubleshooting guides

---

## Terraform

* Improve comments
* Add validations
* Refactor modules

---

## Dashboard

* Add visualizations
* Improve filters
* Add KPIs

---

# 🧠 Learning Outcomes

This project teaches:

* Cloud architecture
* Data engineering
* Infrastructure as Code
* Snowflake data warehousing
* Event-driven pipelines
* CI/CD automation
* IAM security
* Streamlit analytics

---

# 💼 Resume Value

This project demonstrates:

* Enterprise architecture understanding
* AWS cloud experience
* Terraform automation
* Real-world data engineering
* Infrastructure management
* Secure deployment practices

---

# 🎓 Interview Preparation

## Common Questions

### Why use Terraform?

Terraform enables:

* reproducible infrastructure
* version-controlled cloud resources
* automation
* environment consistency

---

### Why Medallion Architecture?

It improves:

* data quality
* scalability
* maintainability
* analytics reliability

---

### Why Snowflake?

Snowflake provides:

* elastic compute
* separation of storage and compute
* scalable analytics
* cloud-native warehousing

---

# 📜 License

Licensed under the MIT License.

---

# 🙌 Acknowledgements

Special thanks to:

* Open-source contributors
* Terraform community
* AWS community
* Snowflake developers
* Data engineering ecosystem

---

# ⭐ Support The Project

If you found this project useful:

* Star the repository
* Fork the project
* Open issues
* Submit pull requests
* Share feedback

---

<div align="center">

# 🚀 Built for Learning Enterprise Cloud Data Engineering

### AWS • Terraform • Snowflake • Streamlit • DevOps • Analytics

</div>
