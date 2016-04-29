from __future__ import print_function
import os
import re
import sys
try:
    from jupyter_client import KernelManager, find_connection_file
except ImportError:
    from IPython.kernel import KernelManager, find_connection_file
try:
    from Queue import Empty
except ImportError:
    from queue import Empty
from glob import glob
from highlighter import highlight

colors = {k: i for i, k in enumerate([
    'black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'])}

traceback_command = """\
%xmode Plain
%colors NoColor
_tb = '\\n'.join(get_ipython().InteractiveTB.structured_traceback(
    *get_ipython()._get_exc_info()))
if not isinstance(_tb, str):
    _tb = _tb.encode('utf-8')
with open('{name}', 'w') as _f:
    _f.write(_tb)
%xmode Context
%colors Linux
""".format(name=os.path.expanduser('~/.pyerr'))


def paths():
    for fullpath in glob(os.path.join(os.path.dirname(filename), 'kernel*')):
        if not re.match('^(.*/)?kernel-[0-9]+.json', fullpath):
            continue
        yield fullpath


connected = False
while not connected:
    try:
        filename = find_connection_file('kernel*')
    except IOError:
        continue

    for fullpath in paths():
        km = KernelManager(connection_file=fullpath)
        km.load_connection_file()

        kc = km.client()
        kc.start_channels()
        try:
            send = kc.execute
        except AttributeError:
            send = kc.shell_channel.execute
        if not hasattr(kc, 'iopub_channel'):
            kc.iopub_channel = kc.sub_channel

        send('', silent=True)
        try:
            msg = kc.shell_channel.get_msg(timeout=1)
            connected = True
            socket = km.connect_iopub()
            print('IPython monitor connected successfully')
            break
        except KeyboardInterrupt:
            sys.exit(0)
        except (Empty, KeyError):
            continue
        except Exception as e:
            import traceback
            traceback.print_exc()
        finally:
            if not connected:
                kc.stop_channels()

if len(sys.argv) > 1:
    term = open(sys.argv[1], 'w+')
    sys.stdout = term


def colorize(string, color, bold=False, bright=False):
    return ''.join(('\033[', str(colors[color] + (90 if bright else 30)),
                    ';1' if bold else '', 'm', string, '\033[0m'))


class IPythonMonitor(object):

    def __init__(self):
        self.clients = set()
        self.execution_count_id = None
        self.last_msg_type = None  # Only set when text written to stdout
        self.last_execution_count = 0

    def print_prompt(self, start='In', color='green', count_offset=0):
        count = str(self.last_execution_count + count_offset)
        sys.stdout.write(colorize(start.rstrip() + ' [', color))
        sys.stdout.write(colorize(count, color, bold=True))
        sys.stdout.write(colorize(']: ', color))
        return '%s [%s]: ' % (start.strip(), count)

    def get_msgs(self):
        try:
            kc.iopub_channel.flush()
            return kc.iopub_channel.get_msgs()
        except AttributeError:
            msgs = []
            while True:
                try:
                    msgs.append(kc.iopub_channel.get_msg(timeout=0.001))
                except Empty:
                    return msgs

    def listen(self):
        while socket.recv():
            for msg in self.get_msgs():
                msg_type = msg['msg_type']

                if msg_type == 'shutdown_reply':
                    sys.exit(0)

                client = msg['parent_header'].get('session', '')
                if (client and msg_type in ('execute_input', 'pyin') and
                        msg['content']['code'] == '"_vim_client";_=_;__=__'):
                    self.clients.add(client)
                    continue
                if client not in self.clients:
                    continue

                getattr(self, msg_type, self.other)(msg)
                sys.stdout.flush()

    def pyin(self, msg):
        self.last_execution_count = msg['content']['execution_count']
        sys.stdout.write('\r')
        dots = '.' * len(self.print_prompt().rstrip()) + ' '
        code = highlight(msg['content']['code'])
        output = code.rstrip().replace('\n', '\n' + dots)
        sys.stdout.write(output)
        self.execution_count_id = msg['parent_header']['msg_id']
        self.last_msg_type = msg['msg_type']

    def pyout(self, msg, prompt=True, spaces=''):
        if 'execution_count' in msg['content']:
            self.last_execution_count = msg['content']['execution_count']
            self.execution_count_id = msg['parent_header']['msg_id']
        if prompt:
            sys.stdout.write('\n')
            spaces = ' ' * len(self.print_prompt('Out', 'red').rstrip()) + ' '
        output = msg['content']['data']['text/plain']
        sys.stdout.write(output.rstrip().replace('\n', '\n' + spaces))
        self.last_msg_type = msg['msg_type']

    def display_data(self, msg):
        sys.stdout.write('\n')
        self.pyout(msg, prompt=False)

    def pyerr(self, msg):
        for line in msg['content']['traceback']:
            sys.stdout.write('\n' + line)
        send(traceback_command, silent=True)
        if self.last_msg_type not in ('execute_input', 'pyin'):
            self.print_prompt('\nIn')
        self.last_msg_type = msg['msg_type']

    def stream(self, msg):
        if self.last_msg_type not in ('pyerr', 'error', 'stream'):
            sys.stdout.write('\n')
        try:
            data = msg['content']['data']
        except KeyError:
            data = msg['content']['text']
        sys.stdout.write(colorize(data, 'cyan', bright=True))
        self.last_msg_type = msg['msg_type']

    def status(self, msg):
        if (msg['content']['execution_state'] == 'idle' and
                msg['parent_header']['msg_id'] == self.execution_count_id):
            self.print_prompt('\nIn', count_offset=1)
            self.execution_count_id = None

    def clear_output(self, msg):
        if self.last_msg_type in ('execute_input', 'pyin'):
            print('\n')
        print('\033[2K\r', file=sys.stdout, end='')

    def other(self, msg):
        print('msg_type = %s' % str(msg['msg_type']))
        print('msg = %s' % str(msg))

    execute_input = pyin
    execute_result = pyout
    error = pyerr


monitor = IPythonMonitor()
monitor.listen()
