import sys

def check_lua_syntax(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    stack = []
    keywords = ['function', 'if', 'for', 'while', 'do']
    
    line_num = 0
    for line in lines:
        line_num += 1
        # remove comments
        code = line.split('--')[0].strip()
        words = code.split()
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
    
    print("✅ Basic keyword matching syntax check passed!")
    return True

if __name__ == "__main__":
    check_lua_syntax("lua/extensions/sft_filter.lua")
