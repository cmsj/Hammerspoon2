/**
 * hs.task JavaScript enhancements
 * Provides a modern async/await API for running external processes
 */

(function() {
    'use strict';

    /**
     * Create and run a task asynchronously
     * @param {string} launchPath - Full path to the executable
     * @param {string[]} args - Array of arguments
     * @param {Object|Function} options - Options object or legacy callback
     * @param {Object} options.environment - Environment variables (optional)
     * @param {string} options.workingDirectory - Working directory (optional)
     * @param {Function} options.onOutput - Callback for streaming output: (stream, data) => {} (optional)
     * @param {Function} legacyStreamCallback - Legacy streaming callback (optional)
     * @returns {Promise<{exitCode: number, stdout: string, stderr: string}>}
     */
    hs.task.run = function(launchPath, args, options, legacyStreamCallback) {
        return new Promise((resolve, reject) => {
            let stdout = '';
            let stderr = '';
            let environment = null;
            let workingDirectory = null;
            let onOutput = null;
            let streamCallback = null;

            // Handle legacy API: hs.task.run(path, args, callback, streamCallback)
            if (typeof options === 'function') {
                const terminationCallback = options;
                streamCallback = legacyStreamCallback;

                const task = hs.task.new.call(hs.task, launchPath, args, terminationCallback, streamCallback);
                task.start();
                return; // Legacy mode doesn't return a promise
            }

            // Modern API with options object
            if (options) {
                environment = options.environment || null;
                workingDirectory = options.workingDirectory || null;
                onOutput = options.onOutput || null;
            }

            // Create streaming callback that accumulates output
            if (onOutput || !onOutput) {
                streamCallback = function(stream, data) {
                    if (stream === 'stdout') {
                        stdout += data;
                    } else if (stream === 'stderr') {
                        stderr += data;
                    }

                    // Call user's onOutput callback if provided
                    if (onOutput) {
                        onOutput(stream, data);
                    }
                };
            }

            // Create termination callback
            const terminationCallback = function(exitCode, reason) {
                const result = {
                    exitCode: exitCode,
                    stdout: stdout,
                    stderr: stderr,
                    reason: reason
                };

                // Reject promise on non-zero exit codes or abnormal termination
                if (exitCode !== 0 || (reason && reason !== 'exit')) {
                    reject(result);
                } else {
                    resolve(result);
                }
            };

            // Create and start the task
            const task = hs.task.new.call(hs.task, launchPath, args, environment, terminationCallback, streamCallback);

            if (workingDirectory) {
                task.setWorkingDirectory(workingDirectory);
            }

            task.start();
        });
    };

    /**
     * Create and run a task asynchronously (alias for run)
     */
    hs.task.async = hs.task.run;

    /**
     * Run a shell command asynchronously
     * @param {string} command - Shell command to execute
     * @param {Object} options - Options (same as run)
     * @returns {Promise<{exitCode: number, stdout: string, stderr: string}>}
     */
    hs.task.shell = function(command, options) {
        return hs.task.run('/bin/sh', ['-c', command], options);
    };

    /**
     * Run multiple tasks in parallel
     * @param {Array} tasks - Array of task specifications: [{path, args, options}, ...]
     * @returns {Promise<Array>} Array of results
     */
    hs.task.parallel = function(tasks) {
        const promises = tasks.map(task =>
            hs.task.run(task.path || task.launchPath, task.args || [], task.options || {})
        );
        return Promise.all(promises);
    };

    /**
     * Run multiple tasks in sequence
     * @param {Array} tasks - Array of task specifications: [{path, args, options}, ...]
     * @returns {Promise<Array>} Array of results
     */
    hs.task.sequence = async function(tasks) {
        const results = [];
        for (const task of tasks) {
            const result = await hs.task.run(task.path || task.launchPath, task.args || [], task.options || {});
            results.push(result);
        }
        return results;
    };

    /**
     * Create a task builder for fluent API
     * @param {string} launchPath - Full path to the executable
     * @returns {TaskBuilder}
     */
    hs.task.builder = function(launchPath) {
        return new TaskBuilder(launchPath);
    };

    /**
     * TaskBuilder class for fluent task construction
     */
    class TaskBuilder {
        constructor(launchPath) {
            this.launchPath = launchPath;
            this.args = [];
            this.env = null;
            this.cwd = null;
            this.outputCallback = null;
        }

        /**
         * Add arguments
         * @param {...string} args - Arguments to add
         * @returns {TaskBuilder}
         */
        withArgs(...args) {
            this.args.push(...args);
            return this;
        }

        /**
         * Set environment variables
         * @param {Object} environment - Environment variables
         * @returns {TaskBuilder}
         */
        withEnvironment(environment) {
            this.env = environment;
            return this;
        }

        /**
         * Set working directory
         * @param {string} directory - Working directory path
         * @returns {TaskBuilder}
         */
        inDirectory(directory) {
            this.cwd = directory;
            return this;
        }

        /**
         * Set output callback
         * @param {Function} callback - Output callback (stream, data) => {}
         * @returns {TaskBuilder}
         */
        onOutput(callback) {
            this.outputCallback = callback;
            return this;
        }

        /**
         * Build and run the task
         * @returns {Promise<{exitCode: number, stdout: string, stderr: string}>}
         */
        async run() {
            const options = {
                environment: this.env,
                workingDirectory: this.cwd,
                onOutput: this.outputCallback
            };
            return hs.task.run(this.launchPath, this.args, options);
        }

        /**
         * Build the task without running
         * @returns {HSTask}
         */
        build() {
            let streamCallback = null;
            if (this.outputCallback) {
                streamCallback = this.outputCallback;
            }

            const task = hs.task.new.call(hs.task, this.launchPath, this.args, this.env, null, streamCallback);

            if (this.cwd) {
                task.setWorkingDirectory(this.cwd);
            }

            return task;
        }
    }

    // Export TaskBuilder for advanced users
    hs.task.TaskBuilder = TaskBuilder;

})();
