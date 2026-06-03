#!/usr/bin/env node
const { execSync } = require('child_process');

let inputData = '';
process.stdin.setEncoding('utf8');

process.stdin.on('data', (chunk) => {
    inputData += chunk;
});

process.stdin.on('end', () => {
    try {
        const input = JSON.parse(inputData);

        // Extract values
        const model = input.model?.display_name || 'Unknown';
        const currentDir = input.workspace?.current_dir || '';
        const ctx = input.context_window || {};
        const totalTokens = ctx.context_window_size || 200000;
        const usedPct = ctx.used_percentage ?? 0;
        const usedTokens = Math.round(totalTokens * usedPct / 100);
        const exceeds200k = input.exceeds_200k_tokens || false;

        // Shorten model name
        const shortModel = model.replace(/^Claude /, '');

        // Get git branch
        let gitBranch = '';
        if (currentDir) {
            try {
                gitBranch = execSync('git rev-parse --abbrev-ref HEAD', {
                    cwd: currentDir,
                    encoding: 'utf8',
                    stdio: ['pipe', 'pipe', 'pipe']
                }).trim();
            } catch (e) {
                // Not a git repo or git not available
            }
        }

        // Get project name (supports both Unix / and Windows \ separators)
        const projectName = currentDir ? currentDir.split(/[/\\]/).pop() : '';

        // Color codes
        const CYAN = '\x1b[36m';
        const YELLOW = '\x1b[33m';
        const RED = '\x1b[31m';
        const BLUE = '\x1b[34m';
        const GREEN = '\x1b[32m';
        const MAGENTA = '\x1b[35m';
        const RESET = '\x1b[0m';

        // Context color: red when >=80% or exceeding 200k, yellow otherwise
        const pctColor = (usedPct >= 80 || exceeds200k) ? RED : YELLOW;
        const warnTag = exceeds200k ? RED + ' !!' + RESET : '';

        // Rate limits: 5-hour (daily-ish session block) and 7-day (weekly)
        const fiveHourPct = input.rate_limits?.five_hour?.used_percentage;
        const sevenDayPct = input.rate_limits?.seven_day?.used_percentage;

        const usageColor = (pct) => pct >= 80 ? RED : (pct >= 50 ? YELLOW : GREEN);

        // Build output
        let output = CYAN + shortModel + RESET;
        output += ' ' + pctColor + usedPct + '%' + RESET + warnTag;

        if (fiveHourPct !== undefined && fiveHourPct !== null) {
            const p = Math.round(fiveHourPct);
            output += ' | day: ' + usageColor(p) + p + '%' + RESET;
        }

        if (sevenDayPct !== undefined && sevenDayPct !== null) {
            const p = Math.round(sevenDayPct);
            output += ' | week: ' + usageColor(p) + p + '%' + RESET;
        }

        if (projectName) {
            output += ' | ' + MAGENTA + projectName + RESET;
        }
        if (gitBranch) {
            output += ' | ' + GREEN + gitBranch + RESET;
        }

        console.log(output);
    } catch (e) {
        console.log('Status line error: ' + e.message);
    }
});
