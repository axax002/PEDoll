﻿using System;
using System.Windows.Forms;
using System.Collections.Generic;

using Mono.Options;

namespace PEDollController.Commands
{

    // Command "target": Shows/switches target client.
    // target[ID]
    // target --lastDoll
    // target --lastMonitor

    class CmdTarget : ICommand
    {
        public string HelpResId() => "Commands.Help.Target";
        public string HelpShortResId() => "Commands.HelpShort.Target";

        public Dictionary<string, object> Parse(string cmd)
        {
            int target = -1;
            bool lastDoll = false;
            bool lastMonitor = false;

            OptionSet options = new OptionSet()
            {
                { "doll", x => lastDoll = (x != null) },
                { "monitor", x => lastMonitor = (x != null) },
                { "<>", (int x) => target = x }
            };
            Util.ParseOptions(cmd, options);

            if (lastDoll && lastMonitor)
                throw new ArgumentException();

            return new Dictionary<string, object>()
            {
                { "verb", "target" },
                { "target", target },
                { "lastDoll", lastDoll },
                { "lastMonitor", lastMonitor }
            };
        }

        public void Invoke(Dictionary<string, object> options)
        {
            int target = (int)options["target"];
            bool lastDoll = (bool)options["lastDoll"];
            bool lastMonitor = (bool)options["lastMonitor"];

            if(target == -1 && !lastDoll && !lastMonitor)
            {
                Logger.I(Program.GetResourceString("Commands.Target.Header"));

                for(int i = 0; i < Threads.Client.theInstances.Count; i++)
                {
                    Threads.Client instance = Threads.Client.theInstances[i];

                    Logger.I(Program.GetResourceString("Commands.Target.Format",
                        (i == Threads.CmdEngine.theInstance.target) ? '*' : ' ',
                        i,
                        instance.clientName,
                        instance.GetTypeString(),
                        instance.GetStatusString(),
                        instance.pid,
                        instance.bits
                    ));
                }
                return;
            }

            if(lastDoll)
                target = Threads.CmdEngine.theInstance.targetLastDoll;
            else if(lastMonitor)
                target = Threads.CmdEngine.theInstance.targetLastMonitor;

            if(target < 0 || target >= Threads.Client.theInstances.Count || Threads.Client.theInstances[target].isDead)
                throw new ArgumentException(Program.GetResourceString("Threads.CmdEngine.TargetNotAvailable"));

            int targetLast = Threads.CmdEngine.theInstance.target;
            Threads.CmdEngine.theInstance.target = target;

            Threads.Client clientLast = Threads.Client.theInstances[targetLast];
            if (clientLast.isMonitor)
                Threads.CmdEngine.theInstance.targetLastMonitor = clientLast.isDead ? target : targetLast;
            else
                Threads.CmdEngine.theInstance.targetLastDoll = clientLast.isDead ? target : targetLast;

            Threads.Client client = Threads.Client.theInstances[target];

            Logger.I(Program.GetResourceString("Commands.Target.CurrentTarget",
                target,
                client.clientName,
                client.GetTypeString(),
                client.GetStatusString()
            ));

            Threads.Gui.theInstance.InvokeOn((FMain Me) => Me.RefreshGuiTargets());
        }
    }

}
