use strict;
use warnings;

local $/;                 # slurp whole file
my $s = <>;

# 1) 让 $$ 单独成行：把单行的 $$...$$ 拆成三行
$s =~ s/^\$\$(.+?)\$\$\s*$/\$\$\n$1\n\$\$/mg;

# 去掉 fenced 属性行：``` {.fenced}  -> ```
$s =~ s/^``` \{\.fenced\}\s*$/```/mg;

# 1b) aligned 环境更整齐：确保 begin/end 和 $$ 都各占一行
$s =~ s/\$\$\s*\\begin\{aligned\}/\$\$\n\\begin{aligned}/g;
$s =~ s/\\end\{aligned\}\s*\$\$/\\end{aligned}\n\$\$/g;

# 2) theorem/lemma：去掉 HTML div 包装（内容保留）
$s =~ s/^\s*<div class="(theorem|lemma)">\s*$//mg;
$s =~ s/^\s*<\/div>\s*$//mg;

# 3) TikZ 空块：删掉空的 center div wrapper
$s =~ s/^\s*<div class="center">\s*$//mg;
$s =~ s/^\s*<\/div>\s*$//mg;

# 小清理：压掉过多空行（最多保留 2 个连续空行）
$s =~ s/\n{4,}/\n\n\n/g;

print $s;
