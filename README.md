# 🍽️ [Soyummy Foods](https://github.com/Dahmii/soyummyfoods)

A full-stack food ordering and management platform built to provide customers with a simple ordering experience while giving administrators the tools to manage the catalogue and ordering workflow.

**Live Demo:** soyummyfoods.vercel.app

## Overview

Soyummy Foods began as a frontend implementation from an existing design and has since evolved into a larger application with customer-facing and administrative workflows.

My work on the project includes translating the original designs into responsive interfaces, developing reusable React components, integrating application data and backend services, and expanding the application architecture as new product requirements were introduced.

## Tech Stack

- React
- TypeScript
- Vite
- Tailwind CSS
- Supabase
- PostgreSQL
- Vercel

## What I worked on

- Responsive customer-facing ordering interfaces
- Reusable React component architecture
- Type-safe frontend development with TypeScript
- Form handling and validation
- Authentication and application state
- Supabase integration and data access
- Administrative catalogue-management workflows
- Loading, error and empty states
- Responsive behaviour across desktop and mobile
- Deployment and environment configuration

## Engineering Focus

One of the main challenges in Soyummy Foods has been evolving the project beyond its initial frontend design into a maintainable application.

As features were introduced, I focused on keeping UI components reusable, separating data-access concerns from presentation logic, handling application states explicitly, and structuring features so that new customer and administrative workflows could be added without tightly coupling them to existing pages.

## Running Locally

```bash
git clone https://github.com/Dahmii/soyummyfoods.git
cd soyummyfoods
npm install
npm run dev
```

Create the required environment variables using `.env.example` before running features that depend on backend services.
