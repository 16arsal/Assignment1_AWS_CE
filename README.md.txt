# Assignment 1 — UniEvent (AWS Deployment)
CE 308/408 Cloud Computing — GIK Institute

## Overview
UniEvent is a cloud-hosted web application that displays "University Events" fetched from a public Open API. The system is deployed on AWS using IAM, VPC, EC2, S3, and Elastic Load Balancing to ensure security, scalability, and fault tolerance.

## Requirements Covered
- Multiple EC2 instances in **private subnets**
- **Elastic Load Balancer** for public access + high availability
- Periodic fetch of event data from an **Open API**
- Event data stored in **S3**
- Uploaded posters/images stored securely in **S3**
- System remains available if one EC2 instance fails (fault tolerance)

---

# Architecture
## AWS Services Used
- **IAM**: EC2 Instance Role for secure S3 access (no hardcoded keys)
- **VPC**: Public + Private subnets across 2 AZs
- **EC2**: Hosts the Flask web application
- **S3**: Stores event JSON + uploaded posters/images
- **Elastic Load Balancer (ALB)**: Routes user traffic to healthy EC2 instances

## Network Design
- Public Subnets: ALB + NAT Gateway
- Private Subnets: EC2 instances
- EC2 instances access Open API via NAT Gateway

(Add your architecture diagram screenshot here)

---

# Step-by-step Deployment Guide

## 1) Create VPC and Subnets
1. Create VPC: `10.0.0.0/16`
2. Create 2 Public Subnets (AZ-a, AZ-b)
3. Create 2 Private Subnets (AZ-a, AZ-b)
4. Attach Internet Gateway
5. Public Route Table: `0.0.0.0/0 -> IGW`
6. Create NAT Gateway in a public subnet
7. Private Route Table: `0.0.0.0/0 -> NAT`

(Screenshots: VPC, Subnets, Route Tables, IGW, NAT)

## 2) Create S3 Buckets
- Bucket 1: `unievent-media-<unique>` (for images/posters)
- Bucket 2: `unievent-events-<unique>` (for events JSON cache)

(Screenshots: Buckets, Block Public Access settings)

## 3) IAM Role for EC2
Create IAM role:
- Trusted entity: EC2
- Permissions: least-privilege S3 access to the two buckets

(Screenshots: Role policy JSON + role attached to instances)

## 4) Security Groups
- ALB Security Group:
  - Inbound: HTTP 80 from `0.0.0.0/0`
- EC2 Security Group:
  - Inbound: App port (e.g. 5000) **ONLY from ALB SG**
  - SSH: optional (only from your IP if needed for debugging)

(Screenshots: SG rules)

## 5) Create Application Load Balancer
- Internet-facing ALB in public subnets
- Target group points to EC2 instances (health check path `/health`)

(Screenshots: ALB listeners + target group healthy checks)

## 6) Auto Scaling Group (2 instances)
- Launch Template includes user-data script to install & run Flask app
- ASG across private subnets
- Desired capacity: 2

(Screenshots: ASG settings + healthy instances)

## 7) Deploy Flask App
- App runs on EC2 in private subnet
- ALB forwards traffic to instances

## 8) Periodic Events Fetch
A scheduled cron job fetches events from Open API and stores `events.json` in S3.
The Flask app reads latest events from S3 and displays them as University Events.

(Screenshots: cron config + S3 events.json)

## 9) Fault Tolerance Demo
- Terminate one EC2 instance manually
- ALB continues serving traffic using the remaining instance
- ASG launches a replacement instance automatically

(Screenshots: before/after termination + ALB still working)

---

# How to Run Locally (Optional)
```bash
cd app
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python main.py