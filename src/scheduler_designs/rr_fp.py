import time
from collections import defaultdict, deque


class Thread:
    def __init__(self, thread_id, priority, burst_time):
        self.thread_id = thread_id
        self.priority = priority
        self.burst_time = burst_time  # total required execution time
        self.remaining_time = burst_time
        self.state = "READY"
        self.arrival_time = time.time() #added arrival time
        self.start_time = None
        self.end_time = None
        self.waiting_time = 0
        self.response_time = None

    def __repr__(self):
        return f"Thread(id={self.thread_id}, pri={self.priority}, rem={self.remaining_time})"


class Scheduler:
    def __init__(self, time_quantum=1):
        self.priority_queues = defaultdict(deque)
        self.priority_levels = []
        self.switches = 0
        self.last_scheduling_time = time.time()
        self.threads = []
        self.time_quantum = time_quantum

    def add_thread(self, thread):
        self.threads.append(thread)
        self.priority_queues[thread.priority].append(thread)
        if thread.priority not in self.priority_levels:
            self.priority_levels.append(thread.priority)
            self.priority_levels.sort(reverse=True)

    def schedule_rr_with_priority(self):
        current_time = time.time()

        for priority in self.priority_levels:
            queue = self.priority_queues[priority]
            queue_len = len(queue)

            for _ in range(queue_len):  # Round Robin loop
                thread = queue.popleft()

                if thread.state == "FINISHED":
                    continue

                # Update waiting time since last scheduled
                if thread.state == "READY":
                    thread.waiting_time += current_time - self.last_scheduling_time

                self.last_scheduling_time = current_time

                # Round-robin: put back if not finished
                queue.append(thread)

                self.switches += 1
                return thread  # scheduled thread

        return None

    def all_finished(self):
        return all(thread.state == "FINISHED" for thread in self.threads)


def thread_function(thread, time_quantum=1):
    print(f"→ Executing Thread {thread.thread_id} for up to {time_quantum:.2f} sec")
    # Simulate execution
    execution_time = min(time_quantum, thread.remaining_time)
    time.sleep(execution_time)  # Simulate actual processing

    thread.remaining_time -= execution_time
    if thread.remaining_time <= 0:
        thread.state = "FINISHED"
        thread.end_time = time.time()
        print(f"✓ Thread {thread.thread_id} FINISHED execution")
    else:
        thread.state = "READY"
        print(f"↪ Thread {thread.thread_id} preempted, remaining: {thread.remaining_time:.2f} sec")


def simulate(scheduler):
    print("\n▶ Starting Round Robin with Priority Scheduling Simulation")
    start_time = time.time()

    total_turnaround_time = 0
    total_waiting_time = 0
    total_response_time = 0

    while not scheduler.all_finished():
        next_thread = scheduler.schedule_rr_with_priority()

        if next_thread is None:
            time.sleep(0.01)  # Idle wait
            continue

        if next_thread.state == "READY":
            next_thread.state = "RUNNING"
            if next_thread.response_time is None:
                next_thread.response_time = time.time() - next_thread.arrival_time
                print(f"↘️ Thread {next_thread.thread_id} RESPONSE at {next_thread.response_time:.2f}s")

        thread_function(next_thread, scheduler.time_quantum)

    end_time = time.time()
    total_time = end_time - start_time

    num_threads = len(scheduler.threads)
    for thread in scheduler.threads:
        turnaround = thread.end_time - thread.arrival_time
        total_turnaround_time += turnaround
        total_waiting_time += thread.waiting_time
        total_response_time += thread.response_time

    print("\n📊 Benchmark Summary")
    print(f"Total Time Taken          : {total_time:.2f} sec")
    print(f"Total Context Switches    : {scheduler.switches}")
    print(f"Avg Turnaround Time       : {total_turnaround_time / num_threads:.2f} sec")
    print(f"Avg Waiting Time          : {total_waiting_time / num_threads:.2f} sec")
    print(f"Avg Response Time         : {total_response_time / num_threads:.2f} sec")
    print(f"Throughput                : {num_threads / total_time:.2f} threads/sec")
    print(f"CPU Utilization           : {(sum(t.burst_time for t in scheduler.threads) / total_time) * 100:.2f}%\n")


def main():
    scheduler = Scheduler(time_quantum=1)  # You can change quantum here

    # Add sample threads
    num_threads = 5
    priorities = [2, 1, 0, 2, 1]
    burst_times = [2, 4, 1, 3, 5]  # Simulated workload in seconds

    for i in range(num_threads):
        thread = Thread(thread_id=i, priority=priorities[i], burst_time=burst_times[i])
        print(f"Created Thread {i} - Priority: {priorities[i]}, Burst Time: {burst_times[i]} sec")
        scheduler.add_thread(thread)

    simulate(scheduler)


if __name__ == "__main__":
    main()
