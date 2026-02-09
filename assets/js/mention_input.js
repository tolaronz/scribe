let MentionInput = {
    mounted() {
        this.input = this.el
        this.hiddenInput = document.getElementById('message-hidden-input')
        this.dropdown = null
        this.currentQuery = ""
        this.isDropdownOpen = false
        this.componentTarget = null

        // Find the component target
        const form = this.input.closest('form')
        if (form && form.hasAttribute('phx-target')) {
            this.componentTarget = form.getAttribute('phx-target')
        }

        this.input.addEventListener("input", (e) => this.handleInput(e))
        this.input.addEventListener("keydown", (e) => this.handleKeydown(e))
        this.input.addEventListener("blur", (e) => this.handleBlur(e))

        this.addHighlightStyles()

        // Listen for contact selection from server
        this.handleEvent("update_contact_highlight", ({ contact_id, display_name, first_name }) => {
            this.updateContactHighlight(contact_id, display_name, first_name)
        })
        // Listen for message sent confirmation from server
        this.handleEvent("clear_input", () => {
            this.clearInput()
        })
        // Listen for scroll to bottom event
        this.handleEvent("scroll_to_bottom", () => {
            this.scrollToBottom()
        })
    },
    addHighlightStyles() {
        if (!document.getElementById('mention-highlight-styles')) {
            const style = document.createElement('style')
            style.id = 'mention-highlight-styles'
            style.textContent = `
                .mention-highlight {
                    background-color: #dbeafe;
                    border: 1px solid #93c5fd;
                    border-radius: 4px;
                    padding: 1px;
                    color: #1e40af;
                    font-weight: 500;
                    line-height: 1.2;
                    display: inline-block;
                    margin: 0 2px;
                }
            `
            document.head.appendChild(style)
        }
    },

    handleInput(event) {
        // Update hidden input with plain text
        const text = this.getPlainText()
        if (this.hiddenInput) {
            this.hiddenInput.value = text
        }

        const cursorPos = this.getCaretPosition()
        const textBeforeCursor = text.substring(0, cursorPos)

        // Find the last @ symbol before cursor
        const lastAtPos = textBeforeCursor.lastIndexOf("@")

        if (lastAtPos !== -1) {
            const mentionText = textBeforeCursor.substring(lastAtPos + 1)

            if (mentionText.length >= 2 && !mentionText.includes(' ')) {
                this.currentQuery = mentionText
                // Push event to component
                this.pushEventTo(this.componentTarget, "search_contacts", {
                    message: text
                })
            }
        }
    },

    handleKeydown(event) {
        // Handle Enter key - Submit on Enter, new line on Shift+Enter
        if (event.key === 'Enter') {
            if (this.isDropdownOpen) {
                // If dropdown is open, select the highlighted item
                event.preventDefault()
                this.selectCurrentItem()
                return
            }

            if (!event.shiftKey) {
                // Enter without Shift = submit form
                event.preventDefault()
                const form = this.input.closest('form')
                if (form) {
                    // Update hidden input before submitting
                    this.updateHiddenInput()

                    // Trigger form submit
                    const submitEvent = new Event('submit', { bubbles: true, cancelable: true })
                    form.dispatchEvent(submitEvent)
                }
                return
            }
            // Shift+Enter = allow default behavior (new line)
        }

        if (event.key === 'Backspace') {
            // Handle backspace on highlighted contact
            const selection = window.getSelection()
            if (selection.rangeCount > 0) {
                const range = selection.getRangeAt(0)
                const node = range.startContainer

                // Check if we're at the start of a highlighted span
                if (node.parentElement && node.parentElement.classList.contains('mention-highlight')) {
                    event.preventDefault()
                    node.parentElement.remove()
                    this.updateHiddenInput()
                    return
                }
            }
        }

        if (!this.isDropdownOpen) return

        switch (event.key) {
            case "ArrowDown":
                event.preventDefault()
                this.navigateDropdown(1)
                break
            case "ArrowUp":
                event.preventDefault()
                this.navigateDropdown(-1)
                break
            case "Escape":
                this.hideDropdown()
                break
        }
    },

    handleBlur(event) {
        setTimeout(() => {
            if (!this.dropdown || !this.dropdown.contains(document.activeElement)) {
                this.hideDropdown()
            }
        }, 150)
    },

    navigateDropdown(direction) {
        if (!this.dropdown) return

        const items = this.dropdown.querySelectorAll("li")
        if (items.length === 0) return

        let currentIndex = -1
        const activeItem = this.dropdown.querySelector("li.bg-slate-100")

        if (activeItem) {
            currentIndex = Array.from(items).indexOf(activeItem)
            activeItem.classList.remove("bg-slate-100")
        }

        currentIndex += direction

        if (currentIndex < 0) currentIndex = items.length - 1
        if (currentIndex >= items.length) currentIndex = 0

        items[currentIndex].classList.add("bg-slate-100")
        items[currentIndex].scrollIntoView({ block: 'nearest' })
    },

    selectCurrentItem() {
        if (!this.dropdown) return

        const activeItem = this.dropdown.querySelector("li.bg-slate-100")
        if (activeItem) {
            const contactId = activeItem.getAttribute('phx-value-id')
            if (contactId) {
                this.selectContact(contactId)
            }
        }
    },

    selectContact(contactId) {
        this.pushEventTo(this.componentTarget, "select_contact", { id: contactId })
        this.hideDropdown()
    },

    hideDropdown() {
        if (this.dropdown) {
            this.dropdown.remove()
            this.dropdown = null
        }
        this.isDropdownOpen = false
    },

    updateContactHighlight(contactId, displayName, firstName) {
        const text = this.getPlainText()
        const html = this.input.innerHTML

        // Find and replace @mention with highlighted span
        const mentionRegex = /@[a-zA-Z\s]+$/
        const match = text.match(mentionRegex)

        if (match) {
            // Get current HTML and replace the mention
            const tempDiv = document.createElement('div')
            tempDiv.innerHTML = html
            const textContent = tempDiv.textContent || tempDiv.innerText

            const mentionStart = textContent.lastIndexOf(match[0])

            if (mentionStart !== -1) {
                const before = textContent.substring(0, mentionStart)
                const after = textContent.substring(mentionStart + match[0].length)

                // Create highlighted span
                const highlightSpan = `<span class="mention-highlight" data-contact-id="${contactId}" data-display-name="${displayName}" contenteditable="false">${firstName}</span>`

                this.input.innerHTML = before + highlightSpan + after

                // Move cursor to end
                const range = document.createRange()
                const sel = window.getSelection()
                range.selectNodeContents(this.input)
                range.collapse(false)
                sel.removeAllRanges()
                sel.addRange(range)

                // Update hidden input
                this.updateHiddenInput()
            }
        }
    },

    clearInput() {
        this.input.innerHTML = ''
        if (this.hiddenInput) {
            this.hiddenInput.value = ''
        }
    },
    getPlainText() {
        // Get plain text from contenteditable, preserving contact references
        let text = ''
        this.input.childNodes.forEach(node => {
            if (node.nodeType === Node.TEXT_NODE) {
                text += node.textContent
            } else if (node.classList && node.classList.contains('mention-highlight')) {
                text += node.textContent
            } else if (node.nodeName === 'BR') {
                text += '\n'
            } else {
                text += node.textContent
            }
        })
        return text
    },

    getCaretPosition() {
        const selection = window.getSelection()
        if (selection.rangeCount === 0) return 0

        const range = selection.getRangeAt(0)
        const preCaretRange = range.cloneRange()
        preCaretRange.selectNodeContents(this.input)
        preCaretRange.setEnd(range.endContainer, range.endOffset)

        return preCaretRange.toString().length
    },

    updateHiddenInput() {
        const text = this.getPlainText()
        if (this.hiddenInput) {
            this.hiddenInput.value = text
        }
    }
}

export default MentionInput
