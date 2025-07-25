import random
from collections import deque
import copy
import matplotlib.pyplot as plt

class Task:
    def __init__(self, tid, execution_time, priority, arrival_time):
        self.tid = tid
        self.total_execution_time = execution_time
        self.remaining_time = execution_time
        self.priority = priority
        self.arrival_time = arrival_time
        self.current_queue = priority
        self.state="READY"
        self.wait_time = 0
        self.turnaround_time = 0
        self.response_time = None
        self.start_time = None
        self.end_time = None
        self.cpu_slices = 0

    def __repr__(self):
        return (f"Task: {self.tid}, rem: {self.remaining_time}, pri: {self.priority}, arrival: {self.arrival_time}")
    
def gen_tasks():
    random.seed(69)
    small_range = (10,100)
    medium_range = (120, 500)
    large_range = (600, 1200)
    very_large_range = (3000, 10000)

    counts = {"small":20, "medium":20, "large":20, "very_large":20}

    exec_times = []
    exec_times.extend([random.randint(*small_range) for _ in range(counts["small"])])
    exec_times.extend([random.randint(*medium_range) for _ in range(counts["medium"])])
    exec_times.extend([random.randint(*large_range) for _ in range(counts["large"])])
    exec_times.extend([random.randint(*very_large_range) for _ in range(counts["very_large"])])

    arrival_times = [random.uniform(0,20000) for _ in range(len(exec_times))]
    tasks = []
    tid = 1
    for et, at in zip(exec_times, arrival_times):
        prio = random.choice([1, 2, 3])
        tasks.append(Task(tid, et, prio, arrival_time=at))
        tid += 1
    return tasks
    
def select_tasks_by_distribution(tasks, count):
    small_tasks = [t for t in tasks if 10 <= t.total_execution_time <= 100]
    medium_tasks = [t for t in tasks if 120 <= t.total_execution_time <= 500]
    large_tasks = [t for t in tasks if 600 <= t.total_execution_time <= 1200]
    very_large_tasks = [t for t in tasks if 3000 <= t.total_execution_time <= 10000]
    total_tasks = 80
    small_count = round(count * 20 / total_tasks)
    medium_count = round(count * 20 / total_tasks)
    large_count = round(count * 20 / total_tasks)
    very_large_count = count - (small_count + medium_count + large_count)

    selected = []
    selected.extend(small_tasks[:small_count])
    selected.extend(medium_tasks[:medium_count])
    selected.extend(large_tasks[:large_count])
    selected.extend(very_large_tasks[:very_large_count])

    return selected
    

class RRPlusPriorityScheduler:
    def __init__(self, tasks, time_quantum=150):
        self.tasks = tasks
        
        self.queues = {1: deque(), 2: deque(), 3: deque()}
        self.time_quantum = time_quantum
        self.clock = 0.0
        self.finished_tasks = []
        self.context_switches = 0
        self.enqueued_tasks = set()

    def all_finished(self):
        return all(t.state=="FINISHED" for t in self.tasks)
    
    def enqueue_arrived_tasks(self):
        for task in self.tasks:
            if (task.arrival_time <= self.clock and 
                task.state != "FINISHED" and 
                task.tid not in self.enqueued_tasks):
                self.queues[task.priority].append(task)
                self.enqueued_tasks.add(task.tid)

    def run(self):
        while not self.all_finished():
            self.enqueue_arrived_tasks()

            ran_task = False
            for prio in [1, 2, 3]: 
                queue = self.queues[prio]
                ready_queue = deque([t for t in queue if t.state != "FINISHED" and t.arrival_time <= self.clock])
                if not ready_queue:
                    continue
                task = ready_queue.popleft()
                self.queues[prio] = deque([t for t in queue if t != task])

                if task.start_time is None:
                    task.start_time = self.clock
                    task.response_time = self.clock - task.arrival_time
                task.state = "RUNNING"
                time_run = min(self.time_quantum, task.remaining_time)
                self.clock += time_run

                for p in [1, 2, 3]:
                    for oth in self.queues[p]:
                        if oth.tid != task.tid and oth.arrival_time <= self.clock and oth.state != "FINISHED":
                            oth.wait_time += time_run

                task.remaining_time -= time_run
                task.cpu_slices += 1
                self.context_switches += 1

                if task.remaining_time <= 0:
                    task.state = "FINISHED"
                    task.end_time = self.clock
                    task.turnaround_time = task.end_time - task.arrival_time
                    self.finished_tasks.append(task)
                    if task.tid in self.enqueued_tasks:
                        self.enqueued_tasks.remove(task.tid)

                else:
                    task.state = "READY"
                    self.queues[prio].append(task)

                ran_task = True
                break

            if not ran_task:
                future_arrivals = [t.arrival_time for t in self.tasks if t.state != "FINISHED" and t.arrival_time > self.clock]
                if not future_arrivals:
                    break
                self.clock = min(future_arrivals)

class MLFQScheduler:
    def __init__(self, tasks, time_quantum=150, levels=3):
        self.tasks = tasks
        self.levels = levels
        self.queues = {i: deque() for i in range(1, levels + 1)}
        self.time_quantum = time_quantum
        self.clock = 0.0
        self.finished_tasks = []
        self.enqueued_tasks = set()
        self.context_switches = 0

    def all_finished(self):
        return all(t.state == "FINISHED" for t in self.tasks)

    def enqueue_arrived_tasks(self):
        for t in self.tasks:
            if t.arrival_time <= self.clock and t.state != "FINISHED" and t.tid not in self.enqueued_tasks:
                t.current_queue = 1
                self.queues[1].append(t)
                self.enqueued_tasks.add(t.tid)

    def run(self):
        while not self.all_finished():
            self.enqueue_arrived_tasks()

            ran_task = False
            for level in range(1, self.levels + 1):
                queue = self.queues[level]
                ready_queue = deque([t for t in queue if t.state != "FINISHED" and t.arrival_time <= self.clock])
                if not ready_queue:
                    continue
                task = ready_queue.popleft()
                self.queues[level] = deque([t for t in queue if t != task])

                if task.start_time is None:
                    task.start_time = self.clock
                    task.response_time = self.clock - task.arrival_time
                task.state = "RUNNING"

                time_run = min(self.time_quantum, task.remaining_time)
                self.clock += time_run

                
                for l in range(1, self.levels + 1):
                    for oth in self.queues[l]:
                        if oth.tid != task.tid and oth.arrival_time <= self.clock and oth.state != "FINISHED":
                            oth.wait_time += time_run
                task.remaining_time -= time_run
                task.cpu_slices += 1
                self.context_switches += 1

                if task.remaining_time <= 0:
                    task.state = "FINISHED"
                    task.end_time = self.clock
                    task.turnaround_time = task.end_time - task.arrival_time
                    self.finished_tasks.append(task)
                    if task.tid in self.enqueued_tasks:
                        self.enqueued_tasks.remove(task.tid)
                else:
                    task.state = "READY"
                    # Demote to next queue if possible
                    if level < self.levels:
                        task.current_queue = level + 1
                        self.queues[level + 1].append(task)
                    else:
                        self.queues[level].append(task)

                ran_task = True
                break
            if not ran_task:
                future_arrivals = [t.arrival_time for t in self.tasks if t.state != "FINISHED" and t.arrival_time > self.clock]
                if not future_arrivals:
                    break
                self.clock = min(future_arrivals)

#Plottinggggg

def run_experiment(tasks):
    tasks_fp = copy.deepcopy(tasks)
    tasks_mlfq = copy.deepcopy(tasks)

    fp_scheduler = RRPlusPriorityScheduler(tasks_fp)
    fp_scheduler.run()

    mlfq_scheduler = MLFQScheduler(tasks_mlfq)
    mlfq_scheduler.run()

    def compute_metrics(finished_tasks, total_time):
        n = len(finished_tasks)
        if n == 0: return 0,0,0
        avg_turnaround = sum(t.turnaround_time for t in finished_tasks) / n
        avg_wait = sum(t.wait_time for t in finished_tasks) / n
        throughput = n / (total_time / 1000) if total_time > 0 else 0
        return avg_turnaround, avg_wait, throughput

    finished_fp = [t for t in fp_scheduler.finished_tasks if t.state == "FINISHED"]
    finished_mlfq = [t for t in mlfq_scheduler.finished_tasks if t.state == "FINISHED"]

    fp_metrics = compute_metrics(finished_fp, fp_scheduler.clock)
    mlfq_metrics = compute_metrics(finished_mlfq, mlfq_scheduler.clock)

    return {
        "fixed_priority": {
            "avg_turnaround": fp_metrics[0],
            "avg_waiting": fp_metrics[1],
            "throughput": fp_metrics[2],
            "runtime": fp_scheduler.clock
        },
        "mlfq": {
            "avg_turnaround": mlfq_metrics[0],
            "avg_waiting": mlfq_metrics[1],
            "throughput": mlfq_metrics[2],
            "runtime": mlfq_scheduler.clock
        }
    }

def plot_results(results, task_counts):
    
    fp_turn = [r['fixed_priority']['avg_turnaround'] for r in results]
    mlfq_turn = [r['mlfq']['avg_turnaround'] for r in results]
    fp_wait = [r['fixed_priority']['avg_waiting'] for r in results]
    mlfq_wait = [r['mlfq']['avg_waiting'] for r in results]
    fp_throughput = [r['fixed_priority']['throughput'] for r in results]
    mlfq_throughput = [r['mlfq']['throughput'] for r in results]
    fp_runtime = [r['fixed_priority']['runtime'] for r in results]
    mlfq_runtime = [r['mlfq']['runtime'] for r in results]

    plt.figure()
    plt.plot(task_counts, fp_turn, label='Fixed Priority RR', marker='o')
    plt.plot(task_counts, mlfq_turn, label='MLFQ', marker='o')
    plt.title("Average Turnaround Time (ms)")
    plt.xlabel("Number of Tasks")
    plt.ylabel("Time (ms)")
    plt.legend()
    plt.grid(True)
    plt.show()

    plt.figure()
    plt.plot(task_counts, fp_runtime, label='Fixed Priority RR', marker='o')
    plt.plot(task_counts, mlfq_runtime, label='MLFQ', marker='o')
    plt.title("Total Runtime (ms)")
    plt.xlabel("Number of Tasks")
    plt.ylabel("Time (ms)")
    plt.legend()
    plt.grid(True)
    plt.show()

    plt.figure()
    plt.plot(task_counts, fp_throughput, label='Fixed Priority RR', marker='o')
    plt.plot(task_counts, mlfq_throughput, label='MLFQ', marker='o')
    plt.title("Throughput (tasks/sec)")
    plt.xlabel("Number of Tasks")
    plt.ylabel("Throughput")
    plt.legend()
    plt.grid(True)
    plt.show()

    plt.figure()
    plt.plot(task_counts, fp_wait, label='Fixed Priority RR', marker='o')
    plt.plot(task_counts, mlfq_wait, label='MLFQ', marker='o')
    plt.title("Average Waiting Time (ms)")
    plt.xlabel("Number of Tasks")
    plt.ylabel("Time (ms)")
    plt.legend()
    plt.grid(True)
    plt.show()


def print_final_metrics(results, task_counts):
    print("\nFinal Metrics for Each Task Count:\n")
    print(f"{'Tasks':>6} | {'Scheduler':>15} | {'Avg Turnaround':>15} | {'Avg Waiting':>12} | {'Throughput':>10} | {'Runtime(ms)':>12}")
    print("-" * 80)
    for i, count in enumerate(task_counts):
        for sched in ['fixed_priority', 'mlfq']:
            metrics = results[i][sched]
            print(f"{count:6} | {sched:15} | {metrics['avg_turnaround']:15.2f} | {metrics['avg_waiting']:12.2f} | {metrics['throughput']:10.2f} | {metrics['runtime']:12.2f}")
        print("-" * 80)


#FINALLY MAIN

if __name__ == "__main__":
    all_tasks = gen_tasks()

   
    task_numbers = [10, 20, 30, 40, 50, 60, 70, 80]

    results = []

    for n in task_numbers:
        selected = select_tasks_by_distribution(all_tasks, n)
        print(f"Running experiment with {n} tasks...")
        res = run_experiment(selected)
        results.append(res)

    plot_results(results, task_numbers)
    print_final_metrics(results, task_numbers)