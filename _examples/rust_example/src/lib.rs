use edg_plugin::*;

fn card_mask(input: String, visible: i64) -> String {
    let chars: Vec<char> = input.chars().collect();
    chars
        .iter()
        .enumerate()
        .map(|(i, &c)| {
            if i < chars.len().saturating_sub(visible as usize) {
                '*'
            } else {
                c
            }
        })
        .collect()
}

fn initials(name: String) -> String {
    name.split_whitespace()
        .filter_map(|w| w.chars().next())
        .map(|c| c.to_uppercase().next().unwrap_or(c))
        .collect()
}

edg_plugin! {
    name: "rust_example",
    functions: {
        card_mask(input: String, visible: i64) -> String,
        "Mask all but the last N characters of a string.",
        "card_mask('4111111111111111', 4)";

        initials(name: String) -> String,
        "Extract uppercase initials from a full name.",
        "initials('Jane Doe')";
    }
}
