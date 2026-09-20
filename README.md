# Nuvo Production Tracker
Mobile-first PWA for epoxy production projects, batches, inventory and shipments.

## Phase 1
Static GitHub Pages-ready frontend with localStorage demo persistence. Shared Supabase backend/auth comes in Phase 2.

## Core rules
- Project quantities are targets, never hard caps.
- Base and activator production are tracked independently.
- Available stock = produced - shipped.
- Complete sets = min(available base, available activator).
- Default expiry = production date + 1 year.
- Default dilute = Epicure × project dilution rate.
