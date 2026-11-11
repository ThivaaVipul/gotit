package app.gotit

/** Recognising copy actions and notices by their English labels. */
object Words {
    private val copyWord = Regex("\\bcopy\\b", RegexOption.IGNORE_CASE)
    private val copiedWord = Regex("\\bcopied\\b", RegexOption.IGNORE_CASE)
    private val startsWithCopy = Regex("^\\s*copy\\b", RegexOption.IGNORE_CASE)

    /**
     * A button or menu label such as "Copy", "Copy link", "Copy code", or a
     * longer one that starts with Copy ("Copy link https://..."). It only
     * counts when tapped: a selection toolbar showing "Copy" is not a copy.
     */
    fun isCopyLabel(s: String): Boolean = s.isNotBlank() &&
        ((s.length <= 40 && copyWord.containsMatchIn(s)) || (s.length <= 300 && startsWithCopy.containsMatchIn(s)))

    /** A Copy item on screen: a short label, or one that starts with Copy. */
    fun isCopyItem(s: String): Boolean = s.isNotBlank() &&
        ((s.length <= 24 && copyWord.containsMatchIn(s)) || (s.length <= 100 && startsWithCopy.containsMatchIn(s)))

    /** A short notice such as "Copied to clipboard" or "Message copied". */
    fun isCopiedNotice(s: String): Boolean = s.isNotBlank() && s.length <= 80 && copiedWord.containsMatchIn(s)
}
