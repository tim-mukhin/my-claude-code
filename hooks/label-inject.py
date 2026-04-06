#!/usr/bin/env python3
"""UserPromptSubmit hook: fire-and-forget label generation.

Hook mode (stdin JSON): launches background generator on first prompt.
Generate mode (--generate): headless claude --print, writes custom-title to JSONL.
"""
import json, sys, os, subprocess, time, logging

LOG_FILE = os.path.expanduser('~/.claude/label-generate.log')


def hook_mode():
    """Called as UserPromptSubmit hook. Fast, synchronous."""
    # Anti-recursion: skip if inside a claude --print subprocess
    if os.environ.get('CLAUDE_LABEL_GENERATING'):
        sys.exit(0)

    data = json.load(sys.stdin)
    session_id = data.get('session_id', '')
    prompt_text = data.get('prompt', '')
    transcript_path = data.get('transcript_path', '')

    if not (session_id and prompt_text and transcript_path):
        sys.exit(0)

    # Skip if custom-title already exists in JSONL
    if os.path.exists(transcript_path):
        try:
            result = subprocess.run(
                ['grep', '-q', 'custom-title', transcript_path],
                capture_output=True, timeout=2)
            if result.returncode == 0:
                sys.exit(0)
        except:
            pass

    try:
        # preexec_fn=os.setpgrp: new process group (survives parent exit,
        # immune to parent's signals) but SAME session (keeps /dev/tty access).
        # start_new_session=True would create a new session with no controlling
        # terminal, making /dev/tty inaccessible from the background process.
        subprocess.Popen(
            [sys.executable, __file__, '--generate',
             session_id, transcript_path, prompt_text],
            preexec_fn=os.setpgrp,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except:
        pass


def generate_mode():
    """Called as background process. Generates label via headless claude --print."""
    logging.basicConfig(
        filename=LOG_FILE, level=logging.INFO,
        format='%(asctime)s %(levelname)s %(message)s', datefmt='%H:%M:%S'
    )

    session_id = sys.argv[2]
    transcript_path = sys.argv[3]
    prompt_text = sys.argv[4]

    if len(prompt_text.strip()) < 3:
        logging.info(f'[{session_id[:8]}] Skipped: prompt too short')
        sys.exit(0)

    system_prompt = (
        "Extract a short label for this conversation. "
        "Output ONLY the label, no quotes, no explanation, no markdown. "
        "Format: emoji + 1-4 word description of the USER'S GOAL in their language. "
        "Max 30 chars. Describe what THEY want, not what an assistant would do.\n\n"
        "Examples:\n"
        '"найди моё резюме, хочу линкедин обновить" -> "💼 обновить LinkedIn"\n'
        '"где код авторизации? там баг" -> "🐛 фикс авторизации"\n'
        '"implement the plan from plan mode" -> use the plan topic, not "implement plan"\n'
    )

    try:
        result = subprocess.run(
            ['claude', '--print', '--model', 'claude-sonnet-4-6',
             '--no-session-persistence', '--permission-mode', 'bypassPermissions',
             '-p', f'{system_prompt}\nUser message:\n{prompt_text[:500]}'],
            capture_output=True, text=True, timeout=15,
            env={**os.environ, 'DISABLE_AUTOUPDATER': '1', 'CLAUDE_LABEL_GENERATING': '1'}
        )
        label = result.stdout.strip().strip('"').strip("'")
        if not label or len(label) < 2:
            logging.warning(f'[{session_id[:8]}] Empty label. stderr: {result.stderr[:200]}')
            sys.exit(1)
        if len(label) > 40:
            label = label[:40]
    except subprocess.TimeoutExpired:
        logging.warning(f'[{session_id[:8]}] Timed out')
        sys.exit(1)
    except Exception as e:
        logging.error(f'[{session_id[:8]}] Failed: {e}')
        sys.exit(1)

    logging.info(f'[{session_id[:8]}] Label: {label}')

    # Write custom-title to JSONL (for /resume + statusline + all hooks)
    record = json.dumps({
        "type": "custom-title",
        "customTitle": label,
        "sessionId": session_id
    }, ensure_ascii=False, separators=(',', ':'))

    for attempt in range(2):
        try:
            if not os.path.exists(transcript_path):
                if attempt == 0:
                    time.sleep(0.5)
                    continue
                logging.warning(f'[{session_id[:8]}] JSONL not found: {transcript_path}')
                break
            with open(transcript_path, 'a') as f:
                f.write(record + '\n')
            logging.info(f'[{session_id[:8]}] custom-title written to JSONL')
            break
        except Exception as e:
            logging.error(f'[{session_id[:8]}] JSONL write failed: {e}')
            break

    # Update tab title via /dev/tty (works because we use setpgrp, not new session)
    try:
        fd = os.open('/dev/tty', os.O_WRONLY)
        os.write(fd, f'\033]2;✳ {label}\007'.encode())
        os.close(fd)
        logging.info(f'[{session_id[:8]}] OSC written to /dev/tty')
    except Exception as e:
        logging.info(f'[{session_id[:8]}] OSC failed: {e}')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--generate':
        generate_mode()
    else:
        hook_mode()
