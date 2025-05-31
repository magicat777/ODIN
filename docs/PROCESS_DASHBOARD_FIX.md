# Process Dashboard Memory Fix Guide

## The Problem
The Host Process Monitoring dashboard is showing incorrect memory values:
- Shows Virtual Memory instead of Resident (actual RAM)
- Chrome shows as 26TB instead of ~5GB
- Units show as MB but values are in TB/GB

## Quick Fix Through UI

### Option 1: Edit Panel Queries (Easiest)

1. Open the dashboard: http://odin.local:31494
2. Go to: **Dashboards** → **Browse** → **Razer Blade** → **Host Process Monitoring**
3. For each memory panel:
   - Hover over the panel title
   - Click the **three dots** (...)
   - Select **Edit**

4. **Fix "Top Memory Consuming Processes" table:**
   - In the Query tab, change:
     ```
     topk(10, sum by (groupname) (namedprocess_namegroup_memory_bytes) / 1024 / 1024)
     ```
   - To:
     ```
     topk(10, sum by (groupname) (namedprocess_namegroup_memory_bytes{memtype="resident"}))
     ```
   - In the right panel under "Standard options" → Unit: select **Data** → **bytes(IEC)**
   - Click **Apply**

5. **Fix "Process Memory Usage Over Time" graph:**
   - In the Query tab, change:
     ```
     topk(5, sum by (groupname) (namedprocess_namegroup_memory_bytes) / 1024 / 1024 / 1024)
     ```
   - To:
     ```
     topk(5, sum by (groupname) (namedprocess_namegroup_memory_bytes{memtype="resident"}))
     ```
   - In the right panel under "Standard options" → Unit: select **Data** → **bytes(IEC)**
   - Click **Apply**

6. Click **Save dashboard** (💾 icon at top)

### Option 2: Replace Entire Dashboard JSON

1. Open dashboard settings (⚙️ gear icon)
2. Select **JSON Model**
3. Copy the JSON from: `/tmp/process-dashboard-update.json`
4. Replace the entire JSON
5. Click **Save dashboard**

## Expected Results After Fix

Instead of:
- Chrome: 26853 GB
- Node: 69 GB

You'll see:
- Chrome: ~5.5 GB
- Node: ~2.3 GB

## Why This Happened

The process exporter provides multiple memory types:
- `virtual`: All memory mappings (can be huge)
- `resident`: Actual RAM usage (what you want)
- `proportionalResident`: Shared memory divided among processes

The original dashboard was summing ALL memory types, resulting in virtual memory being displayed.