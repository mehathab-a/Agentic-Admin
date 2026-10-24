from langsmith import Client

EXAMPLES = [
    ("What time is it in Tokyo?", "tool_required"),
    ("What time is it in Asia/Kolkata?", "tool_required"),
    ("What is 2+2?", "no_tool"),
    ("Who wrote Hamlet?", "no_tool"),
    ("What's the current time in London and New York?", "tool_required"),
]

def main():
    c = Client()
    name = "agent-platform-tool-routing"
    if c.has_dataset(dataset_name=name):
        ds = c.read_dataset(dataset_name=name)
        if ds.example_count:
            print("Dataset already exists"); return
        print("Dataset exists but is empty; adding examples")
    else:
        ds = c.create_dataset(name)

    c.create_examples(
        inputs=[{'question': q} for q, _ in EXAMPLES],
        outputs=[{"expected": e} for _, e in EXAMPLES],
        dataset_id = ds.id,
    )
    print("Dataset created")

if __name__ == "__main__":
    main()
