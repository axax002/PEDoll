﻿using System;
using System.Threading;
using System.Threading.Tasks;

namespace PEDollController.Threads
{
    class CmdEngine
    {
        public static CmdEngine theInstance = new CmdEngine();
        public static Task theTask = new Task(theInstance.TaskMain);

        BlockingQueue<string> cmdQueue;
        AsyncDataProvider<string> cmdProvider;

        // Stop engine & all tasks created by CmdEngine (Listener, Client*)
        public ManualResetEvent stopTaskEvent;
        public Task stopTaskAsync;

        public void AddCommand(string cmd)
        {
            cmdQueue.BlockingEnqueue(cmd);
        }

        CmdEngine()
        {
            cmdQueue = new BlockingQueue<string>();
            cmdProvider = new AsyncDataProvider<string>(cmdQueue.BlockingDequeue);

            stopTaskEvent = new ManualResetEvent(false);
            stopTaskAsync = new Task(() => stopTaskEvent.WaitOne());
            stopTaskAsync.Start();

            // Register to Program's stop event
            Program.OnProgramEnd += Program_OnProgramEnd;

            // Register Ctrl-C event, so that when we received a Ctrl-C from the console, we stop the engine
            Console.CancelKeyPress += Console_CancelKeyPress;
        }

        ~CmdEngine()
        {
            Console.CancelKeyPress -= Console_CancelKeyPress;
            Program.OnProgramEnd -= Program_OnProgramEnd;
        }

        void TaskMain()
        {
            // TODO: Initialize CmdEngine (if anything needs to be done; should be in constructor?)
            while(true)
            {
                Task<string> taskCmd = cmdProvider.Get();
                int idx = Task.WaitAny(stopTaskAsync, taskCmd);

                if (idx == 0)
                {
                    // stopTaskAsync triggered
                    break;
                }
                else
                {
                    string cmd = taskCmd.Result;

                    Console.ForegroundColor = Logger.colorCmd;
                    Console.WriteLine("> " + cmd);
                    Console.ResetColor();
                    OnCommand(cmd);
                }
            }
        }

        void OnCommand(string cmd)
        {
            try
            {
                Commands.Util.Invoke(cmd);
            }
            catch(ArgumentException e)
            {
                Logger.E(e.Message); // NOTE: e.ParamName is followed
            }
        }

        void Program_OnProgramEnd()
        {
            stopTaskEvent.Set();
        }

        void Console_CancelKeyPress(object sender, ConsoleCancelEventArgs args)
        {
            // Do not just stop the process
            args.Cancel = true;

            // TODO: "UI.CtrlC"
            // "\n< Ctrl-C received, press any key to stop engine... >"
            Logger.N(Program.GetResourceString("UI.CtrlC"));
            Console.ReadKey();

            // Tell TaskMain() about ending task
            stopTaskEvent.Set();
        }
    }
}
