import Foundation

assert(MessageText.normalize("  보고 싶어  \n") == "보고 싶어")
assert(MessageText.normalize("   \n").isEmpty)
assert(MessageText.normalize(String(repeating: "a", count: 121)).count == 120)
print("MessageText self-check passed")
