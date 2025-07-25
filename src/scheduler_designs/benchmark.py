import time
import random
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

from rr_fp import Scheduler as RRScheduler, Thread as RRThread
from mlfq import Scheduler as MLFQScheduler, Thread as MLFQThread


class BenchmarkRunner:
    def __init__(self, scheduler_name, scheduler_class, thread_class):
        self.scheduler_name = scheduler_name
        self.scheduler_class = scheduler_class
        self.thread_class = thread_class
        
       
        self.thread_metrics = []
        self.execution_timeline = []       # list of dicts: {thread_id, timestamp, state}
        self.cpu_busy_intervals = []       # list of (start_time, end_time)
        self.context_switch_times = []     # times when context switches happened
        
        self.sim_start = None
        self.sim_end = None
        
    def run(self, num_threads=20):
        # Setup threads
        random.seed(42)
        start_time = time.time
        priorities = [random.randint(0, 3) for _ in range(num_threads)]
        burst_times = [random.uniform(1, 10) for _ in range(num_threads)]
        arrival_times = [start_time + random.uniform(0, 10) for _ in range(num_threads)]
        
        # Instantiate scheduler
        if self.scheduler_name == "RR":
            scheduler = self.scheduler_class(time_quantum=3)
        else:
            scheduler = self.scheduler_class()
        
        threads = []
        for i in range(num_threads):
            # RRThread constructor supports optional arrival_time, MLFQ requires it explicitly
            t = self.thread_class(thread_id=i, priority=priorities[i], burst_time=burst_times[i], arrival_time=arrival_times[i])
            threads.append(t)
            scheduler.add_thread(t)
        
        # Run simulation with instrumentation hooks
        self.sim_start = time.time
        if self.scheduler_name == "RR":
            self._run_rr(scheduler, threads)
        else:
            self._run_mlfq(scheduler, threads)
        self.sim_end = time.time
        
        # Gather thread metrics in DataFrame
        data = {
            "thread_id": [],
            "scheduler": [],
            "turnaround_time": [],
            "waiting_time": [],
            "response_time": [],
            "arrival_time": [],
            "completion_time": [],
            "burst_time": [],
        }
        for t in threads:
            turnaround = (t.end_time - t.arrival_time) if (t.end_time and t.arrival_time) else 0
            waiting = t.waiting_time if hasattr(t, 'waiting_time') else 0
            response = t.response_time if t.response_time is not None else 0
            completion = t.end_time if t.end_time else 0
            data["thread_id"].append(t.thread_id)
            data["scheduler"].append(self.scheduler_name)
            data["turnaround_time"].append(turnaround)
            data["waiting_time"].append(waiting)
            data["response_time"].append(response)
            data["arrival_time"].append(t.arrival_time if t.arrival_time else 0)
            data["completion_time"].append(completion)
            data["burst_time"].append(t.burst_time)
        
        df = pd.DataFrame(data)
        return df



    def _run_rr(self, scheduler, threads):
        # Wrap rr_fp simulation with state / interval logging
        
        time_quantum = scheduler.time_quantum
        cpu_busy_start = None


        def record_state(thread, state):
            self.execution_timeline.append({
                "thread_id": thread.thread_id if thread else None,
                "timestamp": time.time,
                "state": state,
            })


        def thread_function(thread, time_quantum=1):
            nonlocal cpu_busy_start
            exec_time = min(time_quantum, thread.remaining_time)
            start_exec = time.time


            # Record running start
            record_state(thread, "RUNNING")
            if cpu_busy_start is None:
                cpu_busy_start = start_exec


            time.sleep(exec_time)  # Simulate execution


            end_exec = time.time
            thread.remaining_time -= exec_time


            if thread.remaining_time <= 0:
                thread.state = "FINISHED"
                thread.end_time = end_exec
                record_state(thread, "FINISHED")
                # CPU busy interval ends here
                self.cpu_busy_intervals.append((cpu_busy_start, end_exec))
                cpu_busy_start = None
            else:
                thread.state = "READY"
                record_state(thread, "PREEMPTED")
                # CPU busy period ends here before preemption
                self.cpu_busy_intervals.append((cpu_busy_start, end_exec))
                cpu_busy_start = None


        print(f"\nStarting RR Scheduler Simulation")
        start_time = time.time
        switches = 0


        while not scheduler.all_finished():
            next_thread = scheduler.schedule_rr_with_priority()


            if next_thread is None:
                # Idle CPU
                record_state(None, "IDLE")
                cpu_busy_start = None
                time.sleep(0.01)
                continue


            if next_thread.state == "READY":
                next_thread.state = "RUNNING"
                if next_thread.response_time is None:
                    next_thread.response_time = time.time - next_thread.arrival_time
                    print(f"Thread {next_thread.thread_id} response time: {next_thread.response_time:.2f}")


            record_state(next_thread, "RUNNING")


            thread_function(next_thread, time_quantum)
            switches += 1
            self.context_switch_times.append(time.time)


        end_time = time.time
        print(f"RR Scheduler finished in {end_time - start_time:.2f}s with {switches} context switches.")


    def _run_mlfq(self, scheduler, threads):
        # Wrap mlfq simulation with instrumentation
        
        print(f"\nStarting MLFQ Scheduler Simulation")
        
        current_thread = None
        quantum_used = 0
        cpu_busy_start = None


        while not scheduler.all_threads_finished():
            now = time.time


            # Promotions according to original scheduler code
            if now - scheduler.last_promotion_time >= scheduler.global_promotion_interval:
                scheduler.promote_all()
                scheduler.last_promotion_time = now


            if now - scheduler.last_random_promotion_time >= scheduler.random_promotion_interval:
                scheduler.randomized_promotion()
                scheduler.last_random_promotion_time = now


            next_thread = scheduler.schedule()


            if next_thread is None:
                # Idle CPU
                self.execution_timeline.append({"thread_id": None, "timestamp": time.time, "state": "IDLE"})
                cpu_busy_start = None
                current_thread = None
                quantum_used = 0
                time.sleep(0.01)
                continue


            # Preemption if higher priority thread
            if current_thread and current_thread.state == "RUNNING" and next_thread.priority > current_thread.priority:
                self.execution_timeline.append({"thread_id": current_thread.thread_id,
                                                "timestamp": time.time, "state": "PREEMPTED"})
                current_thread.state = "READY"
                if current_thread not in scheduler.priority_queues[current_thread.priority]:
                    scheduler.priority_queues[current_thread.priority].append(current_thread)
                current_thread = next_thread
                quantum_used = 0
                self.context_switch_times.append(time.time)
                cpu_busy_start = None
            elif current_thread is None or current_thread.state != "RUNNING":
                current_thread = next_thread
                quantum_used = 0
                self.context_switch_times.append(time.time)
                if cpu_busy_start is None:
                    cpu_busy_start = time.time


            tq = scheduler.time_quantums.get(current_thread.priority, None)
            if tq is None:
                execution_time = current_thread.remaining_time
            else:
                execution_time = tq - quantum_used
                execution_time = min(execution_time, current_thread.remaining_time)


            self.execution_timeline.append({"thread_id": current_thread.thread_id,
                                            "timestamp": time.time,
                                            "state": "RUNNING"})


            print(f"\nExecuting Thread {current_thread.thread_id} (Pri={current_thread.priority}) for {execution_time:.2f}s")


            time.sleep(execution_time)
            scheduler.current_time += execution_time
            current_thread.remaining_time -= execution_time
            quantum_used += execution_time


            if current_thread.start_time is None:
                current_thread.start_time = scheduler.current_time - execution_time
            if current_thread.response_time is None:
                current_thread.response_time = current_thread.start_time - current_thread.arrival_time


            if current_thread.remaining_time <= 0:
                current_thread.state = "FINISHED"
                current_thread.end_time = scheduler.current_time
                self.execution_timeline.append({"thread_id": current_thread.thread_id,
                                                "timestamp": scheduler.current_time,
                                                "state": "FINISHED"})
                if cpu_busy_start is not None:
                    self.cpu_busy_intervals.append((cpu_busy_start, scheduler.current_time))
                cpu_busy_start = None
                current_thread = None
                quantum_used = 0
                scheduler.context_switches += 1
                self.context_switch_times.append(time.time)
            else:
                if tq is not None and quantum_used >= tq and current_thread.priority > 0:
                    old_p = current_thread.priority
                    new_p = max(0, old_p - 1)
                    if new_p != old_p:
                        print(f"Demoting Thread {current_thread.thread_id} from {old_p} to {new_p}")
                    current_thread.priority = new_p
                    current_thread.state = "READY"
                    if current_thread not in scheduler.priority_queues[new_p]:
                        scheduler.priority_queues[new_p].append(current_thread)


                    self.context_switch_times.append(time.time)
                    if cpu_busy_start is not None:
                        self.cpu_busy_intervals.append((cpu_busy_start, scheduler.current_time))
                    cpu_busy_start = None
                    current_thread = None
                    quantum_used = 0


        print("MLFQ Scheduler finished simulation.")



# ------ Visualization Functions ------

#PERF
def plot_avg_metrics_bar(df):
    avg = df.groupby('scheduler')[['turnaround_time', 'waiting_time', 'response_time']].mean()
    avg.plot(kind='bar', figsize=(8, 6), title="Average Thread Metrics per Scheduler")
    plt.ylabel("Time (seconds)")
    plt.xlabel("Scheduler")
    plt.tight_layout()
    plt.show()

#PERF
def plot_metrics_boxplot(df):
    plt.figure(figsize=(14,5))
    metrics = ['turnaround_time', 'waiting_time', 'response_time']
    for i, metric in enumerate(metrics, 1):
        plt.subplot(1, 3, i)
        sns.boxplot(x='scheduler', y=metric, data=df)
        plt.title(f"{metric.replace('_',' ').title()} Distribution")
        plt.ylabel("Time (seconds)")
    plt.tight_layout()
    plt.show()

#idts this is working - nvm it is
def plot_gantt_chart_seperated(rr_timeline, mlfq_timeline, rr_title="RR Scheduler Execution Timeline", mlfq_title = "MLFQ Scheduler Execution Timeline"):
    def create_gantt_subplot(ax, execution_timeline, title):
        if not execution_timeline:
            ax.text(0.5, 0.5, "No execution timeline available", ha='center', va='center')
            ax.axis('off')
            return


        # Sort timeline by timestamp
        timeline = sorted(execution_timeline, key=lambda x: x['timestamp'])


        gantt_dict = {}
        for i in range(len(timeline)):
            record = timeline[i]
            tid = record["thread_id"]
            ts = record["timestamp"]
            state = record["state"]


            if tid is None:
                # Idle period, skip for per-thread bars
                continue
            if tid not in gantt_dict:
                gantt_dict[tid] = []


        # Calculate duration until next timestamp
            if i+1 < len(timeline):
                end_ts = timeline[i+1]["timestamp"]
            else:
                end_ts = ts + 0.01  # minimal duration for last


            duration = end_ts - ts
            if duration <= 0:
                continue


            gantt_dict[tid].append((ts, duration, state))
        


        #plt.figure(figsize=(12, 6))
        ybase = 10
        yheight = 6
        yticks = []
        ylabels = []
        colors = {
            "RUNNING": "tab:green",
            "PREEMPTED": "tab:orange",
            "READY": "tab:blue",
            "FINISHED": "tab:grey",
            "IDLE": "tab:red",
        }


        idx = 0
        for tid in sorted(gantt_dict.keys()):
            for start, dur, state in gantt_dict[tid]:
                ax.broken_barh([(start, dur)], (ybase + idx*(yheight+2), yheight),
                               facecolors=colors.get(state, "tab:blue"), edgecolor='black')
            yticks.append(ybase + idx*(yheight+2) + yheight / 2)
            ylabels.append(f"Thread {tid}")
            idx += 1

        ax.set_xlabel("Timestamp (seconds since epoch)")
        ax.set_yticks(yticks)
        ax.set_yticklabels(ylabels)
        ax.set_title(title)
        ax.grid(True)

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 10), sharex=True)

    create_gantt_subplot(ax1, rr_timeline, rr_title)
    create_gantt_subplot(ax2, mlfq_timeline, mlfq_title)

    plt.tight_layout()
    plt.show()

   

#PERF
def plot_cpu_busy_idle(rr_intervals, rr_start, rr_end, mlfq_intervals, mlfq_start, mlfq_end):
    # busy_time = sum(end - start for start, end in cpu_intervals)
    # total = sim_end - sim_start
    # idle_time = total - busy_time
    # plt.bar(["CPU Busy", "CPU Idle"], [busy_time, idle_time], color=["tab:green", "tab:red"])
    # plt.ylabel("Time (seconds)")
    # plt.title("CPU Busy vs Idle Time")
    # plt.tight_layout()
    # plt.show()
    rr_busy = sum(end - start for start, end in rr_intervals)
    rr_total = rr_end - rr_start
    rr_idle = rr_total - rr_busy

    mlfq_busy = sum(end - start for start, end in mlfq_intervals)
    mlfq_total = mlfq_end - mlfq_start
    mlfq_idle = mlfq_total - mlfq_busy

    labels = ['CPU Busy', 'CPU Idle']
    rr_values = [rr_busy, rr_idle]
    mlfq_values = [mlfq_busy, mlfq_idle]

    x = np.arange(len(labels))
    width = 0.35

    fig, ax = plt.subplots(figsize=(8,5))
    rects1 = ax.bar(x - width/2, rr_values, width, label='RR Scheduler', color='tab:blue')
    rects2 = ax.bar(x + width/2, mlfq_values, width, label='MLFQ Scheduler', color='tab:orange')

    ax.set_ylabel('Time (seconds)')
    ax.set_title('CPU Busy vs Idle Time Comparison')
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.legend()

    plt.tight_layout()
    plt.show()

#PERF
def plot_context_switch_hist(rr_context_switch_times, mlfq_context_switch_times):
    if len(rr_context_switch_times) < 2:
        print("Not enough context switch events for histogram")
        return
    if len(mlfq_context_switch_times) < 2:
        print("Not enough context switch events for histogram")
        return
    fig, axes = plt.subplots(1, 2, figsize=(14,6))

    # Plot RR context switch intervals histogram
    if len(rr_context_switch_times) >= 2:
        rr_intervals = np.diff(sorted(rr_context_switch_times))
        axes[0].hist(rr_intervals, bins=20, color="tab:blue", alpha=0.7)
        axes[0].set_title("RR Scheduler Context Switch Intervals")
        axes[0].set_xlabel("Interval between context switches (seconds)")
        axes[0].set_ylabel("Frequency")
    else:
        axes[0].text(0.5, 0.5, "Insufficient data", ha='center', va='center')
        axes[0].set_title("RR Scheduler Context Switch Intervals")
        axes[0].set_xticks([])
        axes[0].set_yticks([])

     # Plot MLFQ context switch intervals histogram
    if len(mlfq_context_switch_times) >= 2:
        mlfq_intervals = np.diff(sorted(mlfq_context_switch_times))
        axes[1].hist(mlfq_intervals, bins=20, color="tab:orange", alpha=0.7)
        axes[1].set_title("MLFQ Scheduler Context Switch Intervals")
        axes[1].set_xlabel("Interval between context switches (seconds)")
        axes[1].set_ylabel("Frequency")
    else:
        axes[1].text(0.5, 0.5, "Insufficient data", ha='center', va='center')
        axes[1].set_title("MLFQ Scheduler Context Switch Intervals")
        axes[1].set_xticks([])
        axes[1].set_yticks([])

    plt.tight_layout()
    plt.show()


# -------- Main function to run benchmarks and plot -----------


def main():
    rr_runner = BenchmarkRunner("RR", RRScheduler, RRThread)
    mlfq_runner = BenchmarkRunner("MLFQ", MLFQScheduler, MLFQThread)

    rr_context_switch_times = rr_runner.context_switch_times
    mlfq_context_switch_times = mlfq_runner.context_switch_times



    print("Running RR Scheduler...")
    rr_metrics = rr_runner.run(num_threads=20)
    print("Running MLFQ Scheduler...")
    mlfq_metrics = mlfq_runner.run(num_threads=20)


    # Print summary for RR
    print("\n===== Round Robin Scheduler Summary =====")
    rr_avg = rr_metrics[['turnaround_time', 'waiting_time', 'response_time']].mean()
    rr_throughput = len(rr_metrics) / (rr_runner.sim_end - rr_runner.sim_start)
    print(f"Average Turnaround Time : {rr_avg.turnaround_time:.4f} seconds")
    print(f"Average Waiting Time    : {rr_avg.waiting_time:.4f} seconds")
    print(f"Average Response Time   : {rr_avg.response_time:.4f} seconds")
    print(f"Throughput             : {rr_throughput:.4f} threads/second")


    # Print summary for MLFQ
    print("\n===== MLFQ Scheduler Summary =====")
    mlfq_avg = mlfq_metrics[['turnaround_time', 'waiting_time', 'response_time']].mean()
    mlfq_throughput = len(mlfq_metrics) / (mlfq_runner.sim_end - mlfq_runner.sim_start)
    print(f"Average Turnaround Time : {mlfq_avg.turnaround_time:.4f} seconds")
    print(f"Average Waiting Time    : {mlfq_avg.waiting_time:.4f} seconds")
    print(f"Average Response Time   : {mlfq_avg.response_time:.4f} seconds")
    print(f"Throughput             : {mlfq_throughput:.4f} threads/second")


    combined_metrics = pd.concat([rr_metrics, mlfq_metrics], ignore_index=True)
    combined_timeline = rr_runner.execution_timeline + mlfq_runner.execution_timeline
    combined_cpu_intervals = rr_runner.cpu_busy_intervals + mlfq_runner.cpu_busy_intervals
    combined_context_switch_times = rr_runner.context_switch_times + mlfq_runner.context_switch_times


    plot_avg_metrics_bar(combined_metrics)
    plot_metrics_boxplot(combined_metrics)
    #plot_gantt_chart(combined_timeline, "Thread Execution Timeline (RR and MLFQ)")
    plot_gantt_chart_seperated(rr_runner.execution_timeline, mlfq_runner.execution_timeline)


    sim_start = min(rr_runner.sim_start, mlfq_runner.sim_start)
    sim_end = max(rr_runner.sim_end, mlfq_runner.sim_end)
    #plot_cpu_busy_idle(combined_cpu_intervals, sim_start, sim_end)
    plot_cpu_busy_idle(rr_runner.cpu_busy_intervals, rr_runner.sim_start, rr_runner.sim_end,
                       mlfq_runner.cpu_busy_intervals, mlfq_runner.sim_start, mlfq_runner.sim_end)

    plot_context_switch_hist(rr_context_switch_times, mlfq_context_switch_times)



if __name__ == "__main__":
    main()
