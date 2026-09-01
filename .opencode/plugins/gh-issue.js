/**
 * gh-issue plugin for OpenCode.ai
 *
 * Auto-registers the skills directory via the config hook (no symlinks needed).
 *
 * Unlike superpowers, this plugin injects no per-session bootstrap context.
 * These skills are always invoked explicitly against a named issue or
 * discussion, so OpenCode's native `skill` tool discovering them is all that is
 * needed. Four of the six mutate a live GitHub repo, which is a further reason
 * not to keep them in the preamble.
 */

import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const GhIssuePlugin = async () => {
  const ghIssueSkillsDir = path.resolve(__dirname, '../../skills');

  return {
    // Inject skills path into live config so OpenCode discovers gh-issue skills
    // without requiring manual symlinks or config file edits.
    // This works because Config.get() returns a cached singleton — modifications
    // here are visible when skills are lazily discovered later.
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(ghIssueSkillsDir)) {
        config.skills.paths.push(ghIssueSkillsDir);
      }
    },
  };
};
