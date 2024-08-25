#!/usr/bin/env python3

import argparse
import binascii
import collections
import contextlib
import dataclasses
import os
import re
import subprocess
import sys


class Logcat:

    RX = {
        name: r'(?P<{}>{})'.format(name, rx) for name, rx in (
            # The package name can contain uppercase or lowercase letters, numbers, and
            # underscores ('_'). However, individual package name parts can only start
            # with letters. At least 2 parts long.
            ('package', r'{0} (?:\.{0})+'.format(r'[A-Za-z][_0-9A-Za-z]*')),
            # Process ID.
            ('pid', r'\d+'),
            # Priority.
            ('priority', r'[VDIWEF]'),
            # Tag: can be empty, and in theory contain pretty much any
            # characters unfortunately, but we'll restrict to not start
            # or end with whitespace or ":", end not contain ": " or runs
            # of more than one whitespace.
            ('tag', r'(?:[^ :	][: ](?=[^ :	])|[^ :	])*'),
            # Text (can be empty).
            ('text', r'.*'),
            # Thread ID.
            ('tid', r'\d+'),
            # Time.
            ('time', r'\d+:\d+:\d+\.\d+'),
        )
    }

    LOGCAT_BRIEF_LINE_RX = re.compile(
        # V/KOReader(32615): HttpInspector: onCloseWidget
        r'{priority} / {tag} \s* \( \s* {pid} \) :[ ]? {text}'
        .format(**RX), re.X,
    )
    LOGCAT_THREADTIME_LINE_RX = re.compile(
        # 08-19 23:41:39.347 10000 10023 V KOReader: HttpInspector: onCloseWidget
        r'\d+-\d+ \s+ {time} \s+ {pid} \s+ {tid} \s+ {priority} \s+ {tag} \s* :[ ]? {text}'
        .format(**RX), re.X,
    )
    LOGCAT_TIME_LINE_RX = re.compile(
        # 08-18 02:24:43.331 D/KOReader( 2686): ffi.load rt.so.1
        r'\d+-\d+ \s+ {time} \s+ {priority} / {tag} \s* \( \s* {pid} \) :[ ]? {text}'
        .format(**RX), re.X,
    )
    SELF_LINE_RX = re.compile(
        # 23:41:39.347 10000:10023            KOReader  V  HttpInspector: onCloseWidget
        r'{time} \s+ {pid} (?: : {tid} )? \s+ {tag} \s{{2}} {priority} \s{{2}} {text}'
        .format(**RX), re.X,
    )
    LINE_RX_LIST = (
        LOGCAT_THREADTIME_LINE_RX,
        LOGCAT_BRIEF_LINE_RX,
        LOGCAT_TIME_LINE_RX,
        SELF_LINE_RX,
    )

    ACTIVITY_MANAGER_DEATH_RX = re.compile(
        # Process org.koreader.launcher.debug (pid 2785) has died
        r'Process [ ] {package} [ ] \( pid [ ] {pid} \) [ ] has [ ] died'
        .format(**RX), re.X,
    )
    ACTIVITY_MANAGER_START_RX1 = re.compile(
        # Start proc 2525:org.koreader.launcher/u0a56 for activity org.koreader.launcher/.MainActivity
        r'Start [ ] proc [ ] {pid} : {package} /'
        .format(**RX), re.X,
    )
    # Start proc org.koreader.launcher.debug for activity org.koreader.launcher.debug/org.koreader.launcher.MainActivity: pid=2686 uid=10047 gids={50047, 3003, 1028, 1015}
    ACTIVITY_MANAGER_START_RX2 = re.compile(
        r'Start [ ] proc [ ] {package} [ ] .* \b pid={pid} \b'
        .format(**RX), re.X,
    )
    ACTIVITY_MANAGER_RX_LIST = (
        ACTIVITY_MANAGER_DEATH_RX,
        ACTIVITY_MANAGER_START_RX1,
        ACTIVITY_MANAGER_START_RX2,
    )

    HIGHLIGHT_PACKAGE_RX_TEMPLATE = r'\b (?:{}) \b'
    HIGHLIGHT_PID_RX_TEMPLATE = r'\b pid (?:=|:?[ ]) {} \b'

    COLOR_FORMATS = {
        'reset'  : '\033[0m',
        'bold'   : '\033[1m',
        'dim'    : '\033[2m',
        'reverse': '\033[7m',
        # Priorities.
        'V'      : '\033[37;40m',
        'D'      : '\033[30;44m',
        'I'      : '\033[30;42m',
        'W'      : '\033[30;43m',
        'E'      : '\033[30;41m',
        'F'      : '\033[30;45m',
    }
    NB_BASE_COLORS = 7
    # Colors:
    # - dim variants
    for n in range(NB_BASE_COLORS):
        COLOR_FORMATS['color%u' % (n + NB_BASE_COLORS * 0)] = '\033[2;%um' % (31 + n)
    # - normal variants
    for n in range(NB_BASE_COLORS):
        COLOR_FORMATS['color%u' % (n + NB_BASE_COLORS * 1)] = '\033[%um' % (31 + n)
    # - bold variants
    for n in range(NB_BASE_COLORS):
        COLOR_FORMATS['color%u' % (n + NB_BASE_COLORS * 2)] = '\033[1;%um' % (31 + n)

    LINE_FORMAT = '{time} {proc} {tag} {priority} {text}'
    MAX_PID_LEN = 5
    MAX_TAG_LEN = 25

    Record = collections.namedtuple('Record', 'time pid tid priority tag text')

    @dataclasses.dataclass
    class Group:
        gid   : str       = None
        lines : list[str] = dataclasses.field(default_factory=list)
        show  : bool      = False

    def __init__(self, color=None, packages=None, tags=None):
        if color is None:
            color = sys.stdout.isatty() or os.environ.get('CLICOLOR_FORCE')
        self.color = color
        self.packages = set(packages.split(',')) if packages else set()
        self.tags = set(tags.split(',')) if tags else set()
        self.backlog = self.group = self.hl_rx = self.pids = None
        self.reset()

    def _highlight(self, s):
        if not self.color:
            return s, self.hl_rx.search(s)
        ns = self.hl_rx.sub(self.COLOR_FORMATS['bold'] + r'\1' + self.COLOR_FORMATS['reset'], s)
        return ns, ns != s

    def _format(self, s, colors='', ellipsis=False, max_width=0):
        l = len(s)
        w = abs(max_width) or l
        if l > w:
            l = w
            s = s[:w-1] + '…' if ellipsis else s[:w]
        if colors and self.color:
            for c in colors.split('+'):
                s = self.COLOR_FORMATS.get(c, '') + s
            s += self.COLOR_FORMATS['reset']
        if l < w:
            pad = ' ' * (w - l)
            if max_width < 0:
                s = s + pad
            else:
                s = pad + s
        return s

    def _tag_color(self, tag, app=False):
        if not tag or not self.color:
            return ''
        # Stable colors across runs, color by prefix (first 4 letters).
        c = int(binascii.hexlify(tag[:4].encode()), base=16) % (2 * self.NB_BASE_COLORS)
        if app:
            # No dim colors for application tags, allow bold variants.
            c += self.NB_BASE_COLORS
        return 'color%u' % c

    def _add_package_and_or_pid(self, package=None, pid=None):
        if pid is not None:
            self.pids.add(pid)
        if package is not None:
            self.packages.add(package)
        pids = {str(abs(p)) for p in self.pids}
        self.hl_rx = re.compile('(' + '|'.join(
            # Reverse sort so longer matches are honored.
            rx_tmpl.format('|'.join(map(re.escape, reversed(sorted(s)))))
            for s, rx_tmpl in (
                (self.packages, self.HIGHLIGHT_PACKAGE_RX_TEMPLATE),
                (pids, self.HIGHLIGHT_PID_RX_TEMPLATE),
            )
            # Ignore empty sets.
            if s
        ) + ')', re.X)

    @staticmethod
    def _first_match(rx_list, s, full=False):
        for rx in rx_list:
            m = (rx.fullmatch if full else rx.match)(s)
            if m is not None:
                return m, rx
        return (None, None)

    def _check_for_birth_or_death(self, rec):
        if rec.tag != 'ActivityManager':
            return
        m, rx = self._first_match(self.ACTIVITY_MANAGER_RX_LIST, rec.text)
        if m is None:
            return
        package, pid = m.group('package'), int(m.group('pid'))
        if pid not in self.pids and package not in self.packages:
            return
        if rx is not self.ACTIVITY_MANAGER_DEATH_RX:
            self.backlog = []
        self._add_package_and_or_pid(package=package, pid=pid)

    def _check_for_tags(self, rec):
        if rec.tag not in self.tags:
            # Nope…
            return
        self._add_package_and_or_pid(pid=rec.pid)
        backlog = self.backlog
        self.backlog = []
        for r in backlog:
            self._check_for_birth_or_death(r)
            self._process(r)

    def _update_packages_and_pids(self, rec):
        # Check for startup or death.
        self._check_for_birth_or_death(rec)
        # Check for application tags.
        self._check_for_tags(rec)

    def _process(self, rec):
        gid = (rec.pid, rec.priority, rec.tag)
        if gid != self.group.gid:
            # New group.
            self.group.gid = gid
            self.group.lines = []
            self.group.show = False
        if rec.pid in self.pids:
            # Application record.
            self.group.show = True
            proc_fmt = 'reverse'
            if rec.tid != rec.pid:
                proc_fmt += '+dim'
            tag_fmt = self._tag_color(rec.tag, app=True)
        else:
            # Other record.
            proc_fmt = 'dim'
            tag_fmt = self._tag_color(rec.tag)
        # Highlight text.
        text, match = self._highlight(rec.text)
        if match:
            self.group.show = True
        # Format output line.
        max_tag_len = self.MAX_TAG_LEN
        proc = self._format(str(rec.pid), colors=proc_fmt, max_width=self.MAX_PID_LEN)
        if rec.tid != rec.pid:
            proc += self._format(':' + str(rec.tid), colors=proc_fmt, max_width=-self.MAX_PID_LEN-1)
            max_tag_len -= 1 + self.MAX_PID_LEN
        line = self.LINE_FORMAT.format(
            time=rec.time, proc=proc,
            tag=self._format(rec.tag, colors=tag_fmt, max_width=max_tag_len, ellipsis=True),
            priority=self._format(' ' + rec.priority + ' ', colors=rec.priority),
            text=text,
        )
        if self.group.show:
            for l in self.group.lines:
                print(l)
            print(line)
            self.group.lines.clear()
        else:
            self.group.lines.append(line)

    def reset(self):
        self.backlog = []
        self.group = self.Group()
        self.hl_rx = None
        self.pids = set()

    def filter(self, fd):
        for line in fd:
            if line.startswith('--------- beginning of '):
                continue
            line = line.rstrip('\n')
            if not line:
                # Ignore blank lines.
                continue
            m, _rx = self._first_match(self.LINE_RX_LIST, line, full=True)
            assert m is not None, line
            gd = m.groupdict()
            gd['time'] = gd.get('time', '')
            gd['pid'] = int(gd['pid'])
            gd['tid'] = int(gd.get('tid') or gd['pid'])
            rec = self.Record(**gd)
            self._update_packages_and_pids(rec)
            if self.pids:
                self._process(rec)
            else:
                # Not tracking any PID, append line to backlog.
                self.backlog.append(rec)

def main():
    # Setup parser.
    parser = argparse.ArgumentParser(prog=os.environ.get('PYTHONEXECUTABLE'))
    # Options.
    parser.add_argument('--color', action='store_true',
                        help='force color output', default=None)
    g1 = parser.add_argument_group('logcat mode (default)')
    g1.add_argument('-c', '--clear', action='store_true',
                    help='clear the entire log before running')
    g1.add_argument('-d', '--dump', action='store_true',
                    help='dump the log and then exit (don\'t block)')
    g2 = parser.add_argument_group('filter mode')
    g2.add_argument('-f', '--filter', const='-', metavar='FILE', nargs='?',
                    help='act as a filter: process FILE (stdin by default)')
    # Optional arguments.
    parser.add_argument('packages', nargs='?', help='comma separated list of application packages')
    parser.add_argument('tags', nargs='?', help='comma separated list of application tags')
    # Parse options / arguments.
    args = parser.parse_args()
    if bool(args.clear or args.dump) and bool(args.filter):
        parser.error('logcat and filter options are mutually exclusive')
    if (args.packages, args.tags) == (None, None):
        args.packages = 'org.koreader.launcher,org.koreader.launcher.debug'
        args.tags = 'KOReader,NativeGlue,dlopen,k2pdfopt,libmupdf,luajit-launcher'
    if not args.packages and not args.tags:
        parser.error('no packages and no tags, means there\'s nothing to filter!')
    # Main.
    with contextlib.ExitStack() as stack:
        encoding = sys.stdout.encoding
        # Use line buffering for output.
        stdout = stack.enter_context(open(sys.stdout.fileno(), 'w', buffering=1, closefd=False, encoding=encoding))
        stack.enter_context(contextlib.redirect_stdout(stdout))
        if args.filter:
            # Filter mode.
            if args.filter == '-':
                stdin = sys.stdin
            else:
                stdin = stack.enter_context(open(args.filter, 'r', encoding=encoding))
        else:
            # Logcat mode.
            if args.clear:
                subprocess.check_call(('adb', 'logcat', '-c'))
            cmd = ('adb', 'logcat', '-v', 'threadtime')
            if args.dump:
                cmd += ('-d',)
            stdin = stack.enter_context(subprocess.Popen(cmd, bufsize=1, encoding=encoding, stdout=subprocess.PIPE)).stdout
        Logcat(color=args.color, packages=args.packages, tags=args.tags).filter(stdin)


if __name__ == '__main__':
    main()
