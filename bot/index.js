const { Telegraf } = require('telegraf');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const https = require('https');

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const ALLOWED_CHAT_ID = process.env.ALLOWED_CHAT_ID;

if (!TELEGRAM_BOT_TOKEN || !ALLOWED_CHAT_ID) {
    console.error("FATAL: TELEGRAM_BOT_TOKEN and ALLOWED_CHAT_ID must be set.");
    process.exit(1);
}

const bot = new Telegraf(TELEGRAM_BOT_TOKEN, { handlerTimeout: 9000000 });

// History buffer (last 10 messages)
const rawHistory = [];

// Ensure MyFiles directory exists
const myFilesDir = path.join('/workspace', 'MyFiles');
if (!fs.existsSync(myFilesDir)) {
    fs.mkdirSync(myFilesDir, { recursive: true });
}

// Function to download a file from URL to local destination
function downloadFile(url, dest) {
    return new Promise((resolve, reject) => {
        const file = fs.createWriteStream(dest);
        https.get(url, (response) => {
            if (response.statusCode !== 200) {
                return reject(new Error(`Failed to download '${url}' (${response.statusCode})`));
            }
            response.pipe(file);
            file.on('finish', () => {
                file.close(resolve);
            });
        }).on('error', (err) => {
            fs.unlink(dest, () => reject(err));
        });
    });
}

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
        // Run without shell to avoid command injection and escaping issues.
        // Include '-y' (YOLO mode) to automatically approve agentic tools, otherwise it hangs waiting for stdin Y/n confirmation.
        const child = spawn('gemini', ['-p', prompt, '-y'], { shell: false });
        
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

bot.on(['document', 'photo'], async (ctx) => {
    try {
        let fileId;
        let fileName;
        
        if (ctx.message.document) {
            fileId = ctx.message.document.file_id;
            fileName = ctx.message.document.file_name || `document_${Date.now()}`;
        } else if (ctx.message.photo) {
            // Photos come as an array of resolutions, take the highest one (last item)
            const photo = ctx.message.photo[ctx.message.photo.length - 1];
            fileId = photo.file_id;
            fileName = `photo_${Date.now()}.jpg`;
        }
        
        if (!fileId) return;

        // Ensure valid filename
        fileName = fileName.replace(/[^a-zA-Z0-9.\-_а-яА-ЯёЁ ]/g, '_');
        
        const fileLink = await ctx.telegram.getFileLink(fileId);
        const destPath = path.join(myFilesDir, fileName);
        
        await ctx.sendChatAction('upload_document');
        await downloadFile(fileLink.href, destPath);
        
        // Add to AI context so it knows the file is there
        const infoMsg = `[SYSTEM: Файл загружен пользователем. Путь: /workspace/MyFiles/${fileName}]`;
        rawHistory.push({role: 'user', text: infoMsg});
        rawHistory.push({role: 'assistant', text: "Я принял файл и готов с ним работать."});
        
        // Keep history bounded
        if (rawHistory.length > 10) {
            rawHistory.splice(0, rawHistory.length - 10);
        }
        
        await ctx.reply(`📁 Файл «${fileName}» успешно загружен в папку MyFiles/! Жду команды.`);
        
    } catch (error) {
        console.error("File upload error:", error);
        await ctx.reply(`❌ Ошибка сохранения файла: ${error.message}`);
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
