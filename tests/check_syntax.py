import sys
import re

def check_lua_syntax(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Remove block comments --[[ ... ]]
    content = re.sub(r'--\[\[.*?\]\]', '', content, flags=re.DOTALL)
    # Remove long strings [[ ... ]]
    content = re.sub(r'\[\[.*?\]\]', '""', content, flags=re.DOTALL)
    # Remove line comments -- ...
    content = re.sub(r'--.*', '', content)
    
    lines = content.splitlines()
    
    stack = []
    line_num = 0
    for line in lines:
        line_num += 1
        words = re.findall(r'\b[a-zA-Z_]\w*\b', line)
        for w in words:
            if w in ['function', 'if', 'for', 'while']:
                stack.append((w, line_num))
            elif w == 'end':
                if not stack:
                    print(f"❌ Syntax Error: Unmatched 'end' at line {line_num}")
                    return False
                stack.pop()
    
    if stack:
        print(f"❌ Syntax Error: Unclosed block starting at line {stack[-1][1]} ({stack[-1][0]})")
        return False
    
    print("✅ Lua block structure syntax check passed cleanly!")
    return True

if __name__ == "__main__":
    check_lua_syntax("lua/extensions/sft_filter.lua")
