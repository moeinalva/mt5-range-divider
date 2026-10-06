# MT5 Range Divider

> A lightweight MetaTrader 5 chart utility for dividing a manually selected price range into equal horizontal sections.

**MT5 Range Divider** is a simple and practical chart tool designed for traders who need to quickly divide a price range into **2 or 4 equal sections**.

Select two price levels directly on the chart, choose the desired number of sections, and the tool automatically creates the corresponding horizontal levels.

---

## ✨ Features

* 📏 Select two price levels directly from the chart
* 2-section mode
* 4-section mode
* 📐 Automatic calculation of equal price intervals
* ➖ Uses native MetaTrader 5 horizontal lines
* 🔢 Supports multiple independent ranges on the same chart
* 🎯 Price-based selection — chart time is irrelevant
* 🖱️ Drag the dashboard by its title/header; all controls move together
* ▶️ Enable / Disable selection mode
* 🧹 Clear 2-section ranges, 4-section ranges, or all ranges independently
* 💾 Ranges remain available when changing timeframes
* 🛡️ Handles symbol tick size and price precision
* ⚡ Lightweight with no external dependencies

---

## 📊 How It Works

### 2 Sections

Select two price levels:

```text
Upper Price
──────────────

     50%
──────────────

Lower Price
```

The tool creates:

* 2 boundary levels
* 1 middle divider

---

### 4 Sections

Select two price levels:

```text
Upper Price
──────────────

     75%
──────────────

     50%
──────────────

     25%
──────────────

Lower Price
```

The tool creates:

* 2 boundary levels
* 3 equally spaced dividers

---

## 🖱️ Usage

### 1. Enable Selection

Click:

```text
ENABLE
```

The tool is now waiting for your first price selection.

### 2. Select Point 1

Click anywhere on the chart at your desired price level.

### 3. Select Point 2

Click a second price level.

The two selected prices define your range.

### 4. Choose the Division

Select either:

```text
2 Sections
```

or

```text
4 Sections
```

### 5. Create

Click:

```text
CREATE
```

The tool will create the horizontal levels automatically.

---

## 🔁 Multiple Ranges

You can create multiple independent ranges on the same chart.

For example:

```text
Range #3
──────────────
      │
──────────────
      │
──────────────

Range #2
──────────────
      │
──────────────
      │
──────────────

Range #1
──────────────
      │
──────────────
```

Existing ranges are not modified when a new range is created.

---

## 🧹 Clear Ranges

* **Clear 2 Sections** removes all ranges created in 2-section mode.
* **Clear 4 Sections** removes all ranges created in 4-section mode.
* **Clear All** removes all tool ranges and previews, and switches selection off.

Selective clearing preserves the other range type and the current pending selection. Other objects and drawings on your chart remain untouched.

New ranges store their section count explicitly, so selective clearing continues to work after timeframe changes, indicator reattachment, or manual deletion of individual lines. Ranges from older versions without type metadata can still be removed with **Clear All**; selective clearing leaves them unchanged rather than guessing their type.

## Move the Dashboard

Press and drag the title/header to move the entire dashboard. The panel stays within the main chart where space permits. Dragging and clicking dashboard controls do not select price points. The moved position survives timeframe changes; a fresh attachment uses the configured position. Hover over a shortened status message to read its full text.

---

## ⚙️ Requirements

* **MetaTrader 5**
* Windows
* No external libraries or dependencies

---

## 📦 Installation

1. Download the latest `.ex5` file from the repository's **Releases** section.
2. Open MetaTrader 5.
3. Go to:

```text
File → Open Data Folder
```

4. Navigate to:

```text
MQL5 → Indicators
```

5. Copy:

```text
MT5RangeDivider.ex5
```

into the `Indicators` folder.

6. Restart MetaTrader 5 or refresh the Navigator.
7. Open:

```text
Navigator → Indicators
```

8. Attach **MT5 Range Divider** to your chart.

---

## 🧠 Design Philosophy

MT5 Range Divider is intentionally designed to remain:

* **Simple**
* **Fast**
* **Non-invasive**
* **Trader-controlled**

The tool does not analyze the market, generate signals, or modify trading positions.

It simply helps traders convert a manually selected price range into precise horizontal levels.

---

## 🔒 Source Code

The compiled `.ex5` file is provided for end users.

The MQL5 source code (`MT5RangeDivider.mq5`) is included in this working copy.

---

## 🛠️ Project Structure

```text
mt5-range-divider/
│
├── MT5RangeDivider.mq5
├── MT5RangeDivider.ex5
├── README.md
├── LICENSE
```

---

## 📌 Example Use Cases

MT5 Range Divider can be useful for:

* Price-range analysis
* Intraday market mapping
* Support & resistance planning
* Session range analysis
* Manual trade preparation
* Measuring equal price intervals
* Creating structured chart levels

---

## 📄 License

This project is licensed under the **MIT License**.

See the `LICENSE` file for details.

---

## ⭐ Support

If you find **MT5 Range Divider** useful, consider giving the repository a ⭐ on GitHub.

Issues, suggestions, and feature requests are welcome.
