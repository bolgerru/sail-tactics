class_name Difficulty
extends RefCounted

# Index order is easiest -> hardest.
const NAMES := ["Beginner", "Easy", "Medium", "Hard", "Expert", "Master"]
const LABELS := [
	"Beginner (Easiest)",
	"Easy",
	"Medium",
	"Hard",
	"Expert",
	"Master (Hardest)",
]

const BEGINNER := 0

# Fraction of speed kept by AI boats while tacking.
const TACK_MULT := [0.6, 0.7, 0.8, 0.9, 0.95, 0.98]
# Whether the AI reacts to wind shifts (false = tacks at random).
const USE_WIND_STRATEGY := [false, false, true, true, true, true]
# Per-frame chance the AI reacts when a tack would help.
const REACTION_CHANCE := [0.002, 0.004, 0.005, 0.01, 0.02, 0.05]
