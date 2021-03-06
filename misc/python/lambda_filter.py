import tokenize
from IPython import get_ipython
from IPython.core.prefilter import PrefilterTransformer
from io import StringIO


class LambdaFilter(PrefilterTransformer):
    """IPython prefilter transformer to allow Haskell-like syntax."""

    def transform(self, line, continue_prompt):
        # Don't modify multi-line statements
        if continue_prompt:
            return line
        try:
            list(self.tokens(line))
        except tokenize.TokenError:
            return line

        # Split line on semicolons
        cols = [col for ttype, token, (_, col), _, _
                in self.tokens(line) if ttype == tokenize.OP and token == ';']

        parts = [line[s + 1:e]
                 for s, e in zip([-1] + cols, cols + [len(line)])]
        try:
            parts = [self.parens(part) for part in parts]
        except IndexError:
            return line
        newline = ';'.join(parts)

        # Replace '\' characters with 'lambda '
        cols = [col for _, token, (_, col), _, _
                in self.tokens(newline) if token == '\\' and
                newline[col + 1:].strip() != '']
        for col in reversed(cols):
            newline = newline[:col] + 'lambda ' + newline[col + 1:]

        if newline.strip() != line.strip():
            get_ipython().auto_rewrite_input(newline)

        return newline

    @staticmethod
    def tokens(line):
        try:
            return tokenize.generate_tokens(StringIO(line).readline)
        except tokenize.TokenError:
            return []

    @classmethod
    def parens(cls, line):
        """Replace '$' characters with parentheses."""
        while True:
            found = level = end = None
            start = 0
            stack = []
            for ttype, token, (_, col), _, _ in cls.tokens(line):
                if ttype == tokenize.OP:
                    if token == '(':
                        stack.append(col)
                    elif token == ')':
                        if len(stack) == level:
                            break
                        stack.pop()
                elif not found and token == '$':
                    found = col
                    if stack:
                        start = stack[-1]
                        level = len(stack)
            if not found:
                break
            line = (line[:start] +
                    '(' + line[start:found] + ')' +
                    '(' + line[found + 1:end] + ')' +
                    (line[end:] if end else ''))
        return line


def register():
    unregister()
    LambdaFilter(prefilter_manager=get_ipython().prefilter_manager)


def unregister():
    prefilter_manager = get_ipython().prefilter_manager
    for transformer in prefilter_manager._transformers:
        if isinstance(transformer, LambdaFilter):
            prefilter_manager.unregister_transformer(transformer)
