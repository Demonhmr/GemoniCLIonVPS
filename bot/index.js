const { Telegraf } = require('telegraf');
const { spawn } = require('child_process');

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const ALLOWED_CHAT_ID = process.env.ALLOWED_CHAT_ID;

if (!TELEGRAM_BOT_TOKEN || !ALLOWED_CHAT_ID) {
    console.error("FATAL: TELEGRAM_BOT_TOKEN and ALLOWED_CHAT_ID must be set.");
    process.exit(1);
}

const bot = new Telegraf(TELEGRAM_BOT_TOKEN);

// History buffer (last 10 messages)
const rawHistory = [];

function getContextPrompt(newMessage) {
    if (rawHistory.length === 0) return newMessage;

    let promptStr = "Here is the conversation history so far. Take it into context before answering the final new message.\n\n";
    for(const msg of rawHistory) {
         promptStr += `${msg.role}: ${msg.text}\n\n`;
    }
    promptStr += `user: ${newMessage}\n`;
    return promptStr;
}

function execGemini(prompt) {
    return new Promise((resolve, reject) => {
        // Run without shell to avoid command injection and escaping issues
        const child = spawn('gemini', ['-p', prompt], { shell: false });
        
        let stdout = '';
        let stderr = '';
        
        child.stdout.on('data', data => stdout += data.toString());
        child.stderr.on('data', data => stderr += data.toString());
        
        child.on('close', code => {
            if (code === 0) {
                // Return stdout or stderr (some warnings output to stderr but command succeeds)
                resolve(stdout.trim() || stderr.trim());
            } else {
                reject(new Error(`Exit ${code}.\nStderr: ${stderr}\nStdout: ${stdout}`));
            }
        });
    });
}

bot.use(async (ctx, next) => {
    // Only allow specific chat id
    if (ctx.message && ctx.message.chat && ctx.message.chat.id.toString() !== ALLOWED_CHAT_ID) {
        console.warn(`Unauthorized access attempt from chat id: ${ctx.message.chat.id}`);
        return; // silently ignore
    }
    return next();
});

bot.start((ctx) => ctx.reply('🚀 Gemini CLI Bot ready! I am running via secure container.'));

bot.on('text', async (ctx) => {
    const userText = ctx.message.text;
    
    // Commands to wipe context manually
    if (userText === '/clear') {
        rawHistory.length = 0;
        return ctx.reply("🧹 Context history cleared!");
    }

    try {
        await ctx.sendChatAction('typing');
        
        // Build the prompt containing history
        const prompt = getContextPrompt(userText);
        
        // Push user message to history
        rawHistory.push({role: 'user', text: userText});
        
        console.log(`Executing gemini for message length: ${userText.length}`);
        
        const answer = await execGemini(prompt);
        
        // Push bot answer to history
        rawHistory.push({role: 'assistant', text: answer});
        
        // Keep history bounded to 10 messages (5 pairs)
        if (rawHistory.length > 10) {
            rawHistory.splice(0, rawHistory.length - 10);
        }

        // Send back (Split long messages if they exceed telegram limits 4096 chars)
        const limit = 4000;
        for (let i = 0; i < answer.length; i += limit) {
             const chunk = answer.substring(i, i + limit);
             await ctx.reply(chunk);
        }
        
    } catch (error) {
        console.error("Exec error:", error);
        await ctx.reply(`❌ Error executing Gemini CLI.\n${error.message}`);
    }
});

bot.launch({
    handlerTimeout: 9000000 // 150 minutes timeout to prevent long-running commands from crashing the bot
}).then(() => {
    console.log("🤖 Telegram Bot is running...");
});

// Enable graceful stop
process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
