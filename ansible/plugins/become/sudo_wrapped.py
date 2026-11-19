"""Support sudo PAM stacks that prefix the configured password prompt."""

DOCUMENTATION = r'''
name: sudo_wrapped
short_description: Sudo with support for prefixed password prompts
description:
  - Uses the standard sudo become plugin and recognizes its unique prompt inside a PAM prefix.
options:
  become_user:
    default: root
    vars:
      - name: ansible_become_user
      - name: ansible_sudo_user
    keyword:
      - name: become_user
  become_exe:
    default: sudo
    vars:
      - name: ansible_become_exe
      - name: ansible_sudo_exe
    keyword:
      - name: become_exe
  become_flags:
    default: -H -S -n
    vars:
      - name: ansible_become_flags
      - name: ansible_sudo_flags
    keyword:
      - name: become_flags
  become_pass:
    vars:
      - name: ansible_become_password
      - name: ansible_become_pass
      - name: ansible_sudo_pass
'''

from ansible.module_utils.common.text.converters import to_bytes
from ansible.plugins.become.sudo import BecomeModule as SudoBecomeModule


class BecomeModule(SudoBecomeModule):
    def check_password_prompt(self, output):
        return bool(self.prompt and to_bytes(self.prompt).strip() in output)
