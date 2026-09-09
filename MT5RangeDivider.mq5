#property copyright "OpenAI"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_plots 0

// -----------------------------------------------------------------------------
// MT5 Range Divider
//
// A chart-only utility. It records two prices from chart clicks and creates
// independent OBJ_HLINE levels for a two- or four-section range.
// -----------------------------------------------------------------------------

input group "Object namespace"
input string InpObjectPrefix = "HRD_";

input group "Boundary lines"
input color           InpBoundaryColor       = clrDeepSkyBlue;
input ENUM_LINE_STYLE InpBoundaryStyle       = STYLE_SOLID;
input int             InpBoundaryWidth       = 2;

input group "Divider lines"
input color           InpDividerColor        = clrOrange;
input ENUM_LINE_STYLE InpDividerStyle        = STYLE_DASH;
input int             InpDividerWidth        = 1;

input group "Generated object behavior"
input bool            InpLinesSelectable     = false;
input bool            InpHideGeneratedObjects = false;
input bool            InpDrawLinesInBackground = false;

input group "Selection preview"
input color           InpPreviewColor        = clrSilver;
input ENUM_LINE_STYLE InpPreviewStyle        = STYLE_DOT;
input int             InpPreviewWidth        = 1;

input group "Control panel"
input ENUM_BASE_CORNER InpPanelCorner        = CORNER_LEFT_UPPER;
input int              InpPanelX             = 8;
input int              InpPanelY             = 8;

enum RangeToolState
  {
   STATE_SELECTION_OFF = 0,
   STATE_WAITING_FOR_POINT_1,
   STATE_WAITING_FOR_POINT_2,
   STATE_WAITING_FOR_DIVISION,
   STATE_CREATING_RANGE
  };

long           g_chart_id                    = 0;
RangeToolState g_state                       = STATE_SELECTION_OFF;
bool           g_selection_enabled           = false;
bool           g_has_point_1                 = false;
bool           g_has_point_2                 = false;
double         g_point_1                     = 0.0;
double         g_point_2                     = 0.0;
int            g_selected_sections           = 0;
int            g_panel_x                     = 0;
int            g_panel_y                     = 0;
bool           g_previous_delete_event_state = false;
bool           g_is_deinitializing           = false;
bool           g_bulk_operation              = false;

const int PANEL_WIDTH  = 360;
const int PANEL_HEIGHT = 92;
const int HEADER_HEIGHT = 24;
const int BUTTON_HEIGHT = 22;
const int BUTTON_GAP    = 4;
const int SELECTION_BUTTON_WIDTH = 105;
const int SECTION_BUTTON_WIDTH   = 78;
const int CREATE_BUTTON_WIDTH    = 66;
const int CANCEL_BUTTON_WIDTH    = 66;
const int CLEAR_BUTTON_WIDTH     = 80;

// -----------------------------------------------------------------------------
// Naming helpers
// -----------------------------------------------------------------------------

string UiPrefix()
  {
   return InpObjectPrefix + "UI_";
  }

string RangePrefix()
  {
   return InpObjectPrefix + "Range_";
  }

string PreviewPrefix()
  {
   return InpObjectPrefix + "UI_Preview_";
  }

string UiPanelName()
  {
   return UiPrefix() + "Panel";
  }

string UiHeaderName()
  {
   return UiPrefix() + "Header";
  }

string UiStatusName()
  {
   return UiPrefix() + "Status";
  }

string UiSelectionName()
  {
   return UiPrefix() + "Selection";
  }

string UiSections2Name()
  {
   return UiPrefix() + "Sections_2";
  }

string UiSections4Name()
  {
   return UiPrefix() + "Sections_4";
  }

string UiCreateName()
  {
   return UiPrefix() + "Create";
  }

string UiCancelName()
  {
   return UiPrefix() + "Cancel";
  }

string UiClearName()
  {
   return UiPrefix() + "Clear_All";
  }

string PreviewName(const int index)
  {
   return PreviewPrefix() + IntegerToString(index);
  }

string RangeObjectName(const int range_id,
                       const string role,
                       const int index)
  {
   return StringFormat("%s%06d_%s_%d",
                       RangePrefix(),
                       range_id,
                       role,
                       index);
  }

bool HasPrefix(const string value,
               const string prefix)
  {
   const int prefix_length = StringLen(prefix);
   return StringLen(value) >= prefix_length &&
          StringSubstr(value, 0, prefix_length) == prefix;
  }

// -----------------------------------------------------------------------------
// General helpers
// -----------------------------------------------------------------------------

void LogLastError(const string context)
  {
   const int error_code = GetLastError();
   PrintFormat("HRD: %s (error %d)", context, error_code);
   ResetLastError();
  }

int SafePanelCoordinate(const int coordinate)
  {
   return coordinate < 0 ? 0 : coordinate;
  }

void ClampPanelPosition(int &x,
                        int &y)
  {
   long chart_width = 0;
   long chart_height = 0;
   ChartGetInteger(g_chart_id, CHART_WIDTH_IN_PIXELS, 0, chart_width);
   ChartGetInteger(g_chart_id, CHART_HEIGHT_IN_PIXELS, 0, chart_height);

   x = SafePanelCoordinate(x);
   y = SafePanelCoordinate(y);

   if(chart_width > 0)
     {
      int maximum_x = (int)chart_width - PANEL_WIDTH;
      if(maximum_x < 0)
         maximum_x = 0;
      if(x > maximum_x)
         x = maximum_x;
     }

   if(chart_height > 0)
     {
      int maximum_y = (int)chart_height - PANEL_HEIGHT;
      if(maximum_y < 0)
         maximum_y = 0;
      if(y > maximum_y)
         y = maximum_y;
     }
  }

void InitializePanelPosition()
  {
   g_panel_x = SafePanelCoordinate(InpPanelX);
   g_panel_y = SafePanelCoordinate(InpPanelY);

   const string panel_name = UiPanelName();
   if(ObjectFind(g_chart_id, panel_name) >= 0 &&
      ObjectGetInteger(g_chart_id, panel_name, OBJPROP_TYPE) == OBJ_RECTANGLE_LABEL)
     {
      g_panel_x = (int)ObjectGetInteger(g_chart_id,
                                        panel_name,
                                        OBJPROP_XDISTANCE);
      g_panel_y = (int)ObjectGetInteger(g_chart_id,
                                        panel_name,
                                        OBJPROP_YDISTANCE);
     }

   ClampPanelPosition(g_panel_x, g_panel_y);
  }

void SetUiObjectPosition(const string name,
                         const int x,
                         const int y)
  {
   if(ObjectFind(g_chart_id, name) < 0)
      return;

   ObjectSetInteger(g_chart_id, name, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(g_chart_id, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chart_id, name, OBJPROP_YDISTANCE, y);
  }

void UpdatePanelPositions()
  {
   ClampPanelPosition(g_panel_x, g_panel_y);

   SetUiObjectPosition(UiPanelName(), g_panel_x, g_panel_y);
   SetUiObjectPosition(UiHeaderName(), g_panel_x, g_panel_y);
   SetUiObjectPosition(UiStatusName(), g_panel_x + 8, g_panel_y + 7);

   const int first_row_y = g_panel_y + 32;
   const int second_row_y = g_panel_y + 60;

   int button_x = g_panel_x + 8;
   SetUiObjectPosition(UiSelectionName(), button_x, first_row_y);
   button_x += SELECTION_BUTTON_WIDTH + BUTTON_GAP;
   SetUiObjectPosition(UiSections2Name(), button_x, first_row_y);
   button_x += SECTION_BUTTON_WIDTH + BUTTON_GAP;
   SetUiObjectPosition(UiSections4Name(), button_x, first_row_y);
   button_x += SECTION_BUTTON_WIDTH + BUTTON_GAP;
   SetUiObjectPosition(UiCreateName(), button_x, first_row_y);

   button_x = g_panel_x + 8;
   SetUiObjectPosition(UiCancelName(), button_x, second_row_y);
   button_x += CANCEL_BUTTON_WIDTH + BUTTON_GAP;
   SetUiObjectPosition(UiClearName(), button_x, second_row_y);
  }

bool IsPointInsidePanel(const int x,
                        const int y)
  {
   long chart_width = 0;
   long chart_height = 0;
   ChartGetInteger(g_chart_id, CHART_WIDTH_IN_PIXELS, 0, chart_width);
   ChartGetInteger(g_chart_id, CHART_HEIGHT_IN_PIXELS, 0, chart_height);

   int left = g_panel_x;
   int top = g_panel_y;

   switch(InpPanelCorner)
     {
      case CORNER_LEFT_UPPER:
         break;

      case CORNER_RIGHT_UPPER:
         if(chart_width <= 0)
            return false;
         left = (int)chart_width - g_panel_x - PANEL_WIDTH;
         break;

      case CORNER_LEFT_LOWER:
         if(chart_height <= 0)
            return false;
         top = (int)chart_height - g_panel_y - PANEL_HEIGHT;
         break;

      case CORNER_RIGHT_LOWER:
         if(chart_width <= 0 || chart_height <= 0)
            return false;
         left = (int)chart_width - g_panel_x - PANEL_WIDTH;
         top = (int)chart_height - g_panel_y - PANEL_HEIGHT;
         break;
     }

   return x >= left &&
          x <= left + PANEL_WIDTH &&
          y >= top &&
          y <= top + PANEL_HEIGHT;
  }

int SafeLineWidth(const int width)
  {
   if(width < 1)
      return 1;
   if(width > 5)
      return 5;
   return width;
  }

double SymbolTickSize()
  {
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tick_size <= 0.0)
      tick_size = MathPow(10.0, -_Digits);
   return tick_size;
  }

double NormalizePriceToTick(const double price)
  {
   const double tick_size = SymbolTickSize();
   if(tick_size <= 0.0)
      return NormalizeDouble(price, _Digits);

   const double tick_count = MathRound(price / tick_size);
   return NormalizeDouble(tick_count * tick_size, _Digits);
  }

bool PricesAreEqual(const double first_price,
                    const double second_price)
  {
   const double tolerance = SymbolTickSize() * 0.5;
   return MathAbs(first_price - second_price) <= tolerance;
  }

string FormatPrice(const double price)
  {
   return DoubleToString(price, _Digits);
  }

bool EnsureObjectType(const string name,
                      const ENUM_OBJECT object_type)
  {
   const int existing_subwindow = ObjectFind(g_chart_id, name);
   if(existing_subwindow >= 0)
     {
      const long existing_type = ObjectGetInteger(g_chart_id,
                                                   name,
                                                   OBJPROP_TYPE);
      if(existing_type != object_type)
        {
         PrintFormat("HRD: object name collision for '%s' (type %d, expected %d)",
                     name,
                     existing_type,
                     object_type);
         return false;
        }
      return true;
     }

   ResetLastError();
   if(!ObjectCreate(g_chart_id,
                    name,
                    object_type,
                    0,
                    (datetime)0,
                    0.0))
     {
      LogLastError("failed to create object '" + name + "'");
      return false;
     }
   return true;
  }

bool SetCommonObjectProperties(const string name,
                               const bool selectable,
                               const bool hidden,
                               const bool back)
  {
   bool success = true;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_SELECTABLE, selectable))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_SELECTED, false))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_HIDDEN, hidden))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_BACK, back))
      success = false;
   return success;
  }

bool ConfigureHorizontalLine(const string name,
                             const color line_color,
                             const ENUM_LINE_STYLE line_style,
                             const int line_width,
                             const bool selectable,
                             const bool hidden,
                             const bool back,
                             const string tooltip)
  {
   bool success = true;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_COLOR, line_color))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_STYLE, line_style))
      success = false;
   if(!ObjectSetInteger(g_chart_id,
                        name,
                        OBJPROP_WIDTH,
                        SafeLineWidth(line_width)))
      success = false;
   if(!SetCommonObjectProperties(name, selectable, hidden, back))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_TOOLTIP, tooltip))
      success = false;
   return success;
  }

// -----------------------------------------------------------------------------
// Status and panel
// -----------------------------------------------------------------------------

string StatusWithPoints(const string instruction)
  {
   const string point_1_text = g_has_point_1 ? FormatPrice(g_point_1) : "-";
   const string point_2_text = g_has_point_2 ? FormatPrice(g_point_2) : "-";
   return StringFormat("%s    P1: %s    P2: %s",
                       instruction,
                       point_1_text,
                       point_2_text);
  }

void SetStatus(const string message)
  {
   if(ObjectFind(g_chart_id, UiStatusName()) < 0)
      return;

   ObjectSetString(g_chart_id, UiStatusName(), OBJPROP_TEXT, message);
   ChartRedraw(g_chart_id);
  }

void SetButtonAppearance(const string name,
                         const bool selected,
                         const bool enabled)
  {
   if(ObjectFind(g_chart_id, name) < 0)
      return;

   color background_color = clrGray;
   color text_color       = clrDarkGray;
   if(enabled)
     {
      background_color = selected ? clrDodgerBlue : clrDarkSlateGray;
      text_color       = clrWhite;
     }

   ObjectSetInteger(g_chart_id, name, OBJPROP_BGCOLOR, background_color);
   ObjectSetInteger(g_chart_id, name, OBJPROP_COLOR, text_color);
   ObjectSetInteger(g_chart_id, name, OBJPROP_BORDER_COLOR, clrSilver);
   ObjectSetInteger(g_chart_id, name, OBJPROP_STATE, selected);
  }

void UpdateButtonStates()
  {
   ObjectSetString(g_chart_id,
                   UiSelectionName(),
                   OBJPROP_TEXT,
                   g_selection_enabled ? "Disable selection" : "Enable selection");
   SetButtonAppearance(UiSelectionName(),
                       g_selection_enabled,
                       true);

   const bool range_ready = g_selection_enabled &&
                            g_has_point_1 &&
                            g_has_point_2;
   const bool can_create  = range_ready &&
                            (g_selected_sections == 2 ||
                             g_selected_sections == 4);

   SetButtonAppearance(UiSections2Name(),
                       g_selected_sections == 2,
                       range_ready);
   SetButtonAppearance(UiSections4Name(),
                       g_selected_sections == 4,
                       range_ready);
   SetButtonAppearance(UiCreateName(),
                       can_create,
                       can_create);
   SetButtonAppearance(UiCancelName(), false, true);
   SetButtonAppearance(UiClearName(), false, true);
  }

bool CreateOrUpdateLabel(const string name,
                         const string text,
                         const int x,
                         const int y,
                         const color text_color,
                         const int font_size)
  {
   if(!EnsureObjectType(name, OBJ_LABEL))
      return false;

   bool success = true;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_CORNER, InpPanelCorner))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_XDISTANCE, x))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_YDISTANCE, y))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_COLOR, text_color))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_FONTSIZE, font_size))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_FONT, "Arial"))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_TEXT, text))
      success = false;
   if(!SetCommonObjectProperties(name, false, true, false))
      success = false;
   return success;
  }

bool CreateOrUpdateButton(const string name,
                          const string text,
                          const int x,
                          const int y,
                          const int width)
  {
   if(!EnsureObjectType(name, OBJ_BUTTON))
      return false;

   bool success = true;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_CORNER, InpPanelCorner))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_XDISTANCE, x))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_YDISTANCE, y))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_XSIZE, width))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_YSIZE, BUTTON_HEIGHT))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_ZORDER, 100))
      success = false;
   if(!ObjectSetInteger(g_chart_id, name, OBJPROP_FONTSIZE, 8))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_FONT, "Arial"))
      success = false;
   if(!ObjectSetString(g_chart_id, name, OBJPROP_TEXT, text))
      success = false;
   if(!SetCommonObjectProperties(name, false, true, false))
      success = false;
   return success;
  }

bool CreateControlPanel()
  {
   if(!EnsureObjectType(UiPanelName(), OBJ_RECTANGLE_LABEL))
      return false;
   if(!EnsureObjectType(UiHeaderName(), OBJ_RECTANGLE_LABEL))
      return false;

   bool success = true;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_CORNER, InpPanelCorner))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_XSIZE, PANEL_WIDTH))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_YSIZE, PANEL_HEIGHT))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_BGCOLOR, clrBlack))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_COLOR, clrDimGray))
      success = false;
   // Keep the panel in the foreground so clicks inside its body do not fall
   // through and become price-selection clicks when selection is enabled.
   if(!SetCommonObjectProperties(UiPanelName(), false, true, false))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiPanelName(), OBJPROP_ZORDER, 0))
      success = false;

   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_CORNER, InpPanelCorner))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_XSIZE, PANEL_WIDTH))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_YSIZE, HEADER_HEIGHT))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_BGCOLOR, clrBlack))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_COLOR, clrDimGray))
      success = false;
   if(!SetCommonObjectProperties(UiHeaderName(), true, true, false))
      success = false;
   if(!ObjectSetInteger(g_chart_id, UiHeaderName(), OBJPROP_ZORDER, 10))
      success = false;
   if(!ObjectSetString(g_chart_id,
                       UiHeaderName(),
                       OBJPROP_TOOLTIP,
                       "Drag to move the MT5 Range Divider panel"))
      success = false;

   if(!CreateOrUpdateLabel(UiStatusName(),
                            "HRD Range Divider",
                            g_panel_x + 8,
                            g_panel_y + 7,
                            clrWhite,
                            9))
      success = false;

   if(!CreateOrUpdateButton(UiSelectionName(),
                            "Enable selection",
                            g_panel_x + 8,
                            g_panel_y + 32,
                            SELECTION_BUTTON_WIDTH))
      success = false;

   int button_x = g_panel_x + 8 + SELECTION_BUTTON_WIDTH + BUTTON_GAP;
   if(!CreateOrUpdateButton(UiSections2Name(),
                            "2 sections",
                            button_x,
                            g_panel_y + 32,
                            SECTION_BUTTON_WIDTH))
      success = false;
   button_x += SECTION_BUTTON_WIDTH + BUTTON_GAP;
   if(!CreateOrUpdateButton(UiSections4Name(),
                            "4 sections",
                            button_x,
                            g_panel_y + 32,
                            SECTION_BUTTON_WIDTH))
      success = false;
   button_x += SECTION_BUTTON_WIDTH + BUTTON_GAP;
   if(!CreateOrUpdateButton(UiCreateName(),
                            "Create",
                            button_x,
                            g_panel_y + 32,
                            CREATE_BUTTON_WIDTH))
      success = false;

   button_x = g_panel_x + 8;
   if(!CreateOrUpdateButton(UiCancelName(),
                            "Cancel",
                            button_x,
                            g_panel_y + 60,
                            CANCEL_BUTTON_WIDTH))
      success = false;
   button_x += CANCEL_BUTTON_WIDTH + BUTTON_GAP;
   if(!CreateOrUpdateButton(UiClearName(),
                            "Clear all",
                            button_x,
                            g_panel_y + 60,
                            CLEAR_BUTTON_WIDTH))
      success = false;

   UpdatePanelPositions();
   UpdateButtonStates();
   return success;
  }

// -----------------------------------------------------------------------------
// Preview lines
// -----------------------------------------------------------------------------

bool CreateOrMovePreview(const int index,
                         const double price)
  {
   const string name = PreviewName(index);
   if(!EnsureObjectType(name, OBJ_HLINE))
      return false;

   const double normalized_price = NormalizePriceToTick(price);
   bool success = true;
   if(!ObjectSetDouble(g_chart_id,
                       name,
                       OBJPROP_PRICE,
                       0,
                       normalized_price))
      success = false;
   if(!ConfigureHorizontalLine(name,
                               InpPreviewColor,
                               InpPreviewStyle,
                               InpPreviewWidth,
                               false,
                               false,
                               false,
                               "HRD selection preview"))
      success = false;
   if(!success)
      LogLastError("failed to update preview line '" + name + "'");
   return success;
  }

void DeletePreviewLines()
  {
   ResetLastError();
   ObjectsDeleteAll(g_chart_id, PreviewPrefix());
   ResetLastError();
  }

// -----------------------------------------------------------------------------
// Range management
// -----------------------------------------------------------------------------

bool RangeIdHasAnyObject(const int range_id)
  {
   for(int boundary_index = 1; boundary_index <= 2; boundary_index++)
     {
      if(ObjectFind(g_chart_id,
                    RangeObjectName(range_id,
                                    "Boundary",
                                    boundary_index)) >= 0)
         return true;
     }

   for(int divider_index = 1; divider_index <= 3; divider_index++)
     {
      if(ObjectFind(g_chart_id,
                    RangeObjectName(range_id,
                                    "Divider",
                                    divider_index)) >= 0)
         return true;
     }
   return false;
  }

int FindNextRangeId()
  {
   for(int candidate = 1; candidate < 1000000; candidate++)
     {
      if(!RangeIdHasAnyObject(candidate))
         return candidate;
     }
   return -1;
  }

void DeleteRangeObjects(const int range_id)
  {
   for(int boundary_index = 1; boundary_index <= 2; boundary_index++)
      ObjectDelete(g_chart_id,
                   RangeObjectName(range_id,
                                   "Boundary",
                                   boundary_index));

   for(int divider_index = 1; divider_index <= 3; divider_index++)
      ObjectDelete(g_chart_id,
                   RangeObjectName(range_id,
                                   "Divider",
                                   divider_index));
  }

bool CalculateRangeLevels(const int sections,
                          double &levels[])
  {
   if(sections != 2 && sections != 4)
      return false;

   ArrayResize(levels, sections + 1);
   for(int index = 0; index <= sections; index++)
     {
      const double fraction = (double)index / (double)sections;
      levels[index] = NormalizePriceToTick(g_point_1 +
                                           (g_point_2 - g_point_1) *
                                           fraction);
     }
   return true;
  }

bool LevelsContainOverlap(const double &levels[])
  {
   const int level_count = ArraySize(levels);
   for(int first = 0; first < level_count; first++)
     {
      for(int second = first + 1; second < level_count; second++)
        {
         if(PricesAreEqual(levels[first], levels[second]))
            return true;
        }
     }
   return false;
  }

bool CreateRangeLine(const string name,
                     const double price,
                     const color line_color,
                     const ENUM_LINE_STYLE line_style,
                     const int line_width,
                     const string tooltip)
  {
   if(ObjectFind(g_chart_id, name) >= 0)
     {
      PrintFormat("HRD: refusing to overwrite existing object '%s'", name);
      return false;
     }

   ResetLastError();
   if(!ObjectCreate(g_chart_id,
                    name,
                    OBJ_HLINE,
                    0,
                    (datetime)0,
                    NormalizePriceToTick(price)))
     {
      LogLastError("failed to create range line '" + name + "'");
      return false;
     }

   if(!ConfigureHorizontalLine(name,
                               line_color,
                               line_style,
                               line_width,
                               InpLinesSelectable,
                               InpHideGeneratedObjects,
                               InpDrawLinesInBackground,
                               tooltip))
     {
      LogLastError("failed to configure range line '" + name + "'");
      return false;
     }
   return true;
  }

bool CreateRange(const int sections,
                 int &created_range_id,
                 bool &levels_overlap)
  {
   created_range_id = -1;
   levels_overlap  = false;

   if(!g_has_point_1 || !g_has_point_2)
      return false;
   if(sections != 2 && sections != 4)
      return false;
   if(PricesAreEqual(g_point_1, g_point_2))
      return false;

   double levels[];
   if(!CalculateRangeLevels(sections, levels))
      return false;

   levels_overlap = LevelsContainOverlap(levels);
   const int range_id = FindNextRangeId();
   if(range_id < 0)
     {
      Print("HRD: no available range ID remains");
      return false;
     }

   bool success = true;
   success = CreateRangeLine(
      RangeObjectName(range_id, "Boundary", 1),
      levels[0],
      InpBoundaryColor,
      InpBoundaryStyle,
      InpBoundaryWidth,
      StringFormat("HRD range %06d boundary 1", range_id)) && success;

   success = CreateRangeLine(
      RangeObjectName(range_id, "Boundary", 2),
      levels[sections],
      InpBoundaryColor,
      InpBoundaryStyle,
      InpBoundaryWidth,
      StringFormat("HRD range %06d boundary 2", range_id)) && success;

   for(int divider_index = 1;
       divider_index < sections;
       divider_index++)
     {
      const string divider_name = RangeObjectName(range_id,
                                                   "Divider",
                                                   divider_index);
      const bool divider_created = CreateRangeLine(
         divider_name,
         levels[divider_index],
         InpDividerColor,
         InpDividerStyle,
         InpDividerWidth,
         StringFormat("HRD range %06d divider %d",
                      range_id,
                      divider_index));
      success = divider_created && success;
     }

   if(!success)
     {
      DeleteRangeObjects(range_id);
      return false;
     }

   created_range_id = range_id;
   return true;
  }

void ClearCurrentSelection()
  {
   DeletePreviewLines();
   g_has_point_1       = false;
   g_has_point_2       = false;
   g_point_1           = 0.0;
   g_point_2           = 0.0;
   g_selected_sections = 0;
   g_state             = g_selection_enabled
                         ? STATE_WAITING_FOR_POINT_1
                         : STATE_SELECTION_OFF;
   UpdateButtonStates();
  }

void ClearAllRanges()
  {
   g_bulk_operation = true;
   ResetLastError();
   const int deleted_ranges = ObjectsDeleteAll(g_chart_id, RangePrefix());
   const int deleted_preview = ObjectsDeleteAll(g_chart_id, PreviewPrefix());
   ResetLastError();
   g_selection_enabled = false;
   ClearCurrentSelection();
   g_bulk_operation = false;

   SetStatus(StringFormat("Cleared %d range objects and %d preview objects. Selection OFF. Click Enable selection.",
                          deleted_ranges,
                          deleted_preview));
   ChartRedraw(g_chart_id);
  }

// -----------------------------------------------------------------------------
// Interaction handling
// -----------------------------------------------------------------------------

void HandleChartClick(const long x_coordinate,
                      const long y_coordinate)
  {
   // A button/object click can also arrive as CHARTEVENT_CLICK on some
   // terminal builds. Consume every click inside the panel before doing any
   // price conversion so UI clicks can never become Point 1 or Point 2.
   if(IsPointInsidePanel((int)x_coordinate, (int)y_coordinate))
      return;

   if(!g_selection_enabled || g_state == STATE_SELECTION_OFF)
      return;

   int sub_window = 0;
   datetime click_time = 0;
   double clicked_price = 0.0;
   ResetLastError();
   if(!ChartXYToTimePrice(g_chart_id,
                          (int)x_coordinate,
                          (int)y_coordinate,
                          sub_window,
                          click_time,
                          clicked_price))
     {
      LogLastError("could not convert chart click to a price");
      SetStatus("Click conversion failed. Try inside the main price chart.");
      return;
     }

   // The time returned above is intentionally unused. This utility is price-only.
   if(sub_window != 0)
     {
      SetStatus("Click inside the main price chart window.");
      return;
     }

   clicked_price = NormalizePriceToTick(clicked_price);

   if(g_state == STATE_WAITING_FOR_POINT_1)
     {
      g_point_1     = clicked_price;
      g_point_2     = 0.0;
      g_has_point_1 = true;
      g_has_point_2 = false;
      g_selected_sections = 0;
      DeletePreviewLines();
      CreateOrMovePreview(1, g_point_1);
      g_state = STATE_WAITING_FOR_POINT_2;
      UpdateButtonStates();
      SetStatus(StatusWithPoints("Point 1 selected. Click point 2."));
      return;
     }

   if(g_state == STATE_WAITING_FOR_POINT_2)
     {
      if(PricesAreEqual(g_point_1, clicked_price))
        {
         SetStatus(StatusWithPoints("Point 2 matches point 1. Click a different price."));
         return;
        }

      g_point_2     = clicked_price;
      g_has_point_2 = true;
      CreateOrMovePreview(2, g_point_2);
      g_state = STATE_WAITING_FOR_DIVISION;
      UpdateButtonStates();
      SetStatus(StatusWithPoints("Choose 2 or 4 sections, then Create."));
      return;
     }

   if(g_state == STATE_WAITING_FOR_DIVISION)
     {
      SetStatus(StatusWithPoints("Choose a section count or Cancel before starting again."));
      return;
     }

   SetStatus("Creating range. Please wait...");
  }

void HandleButtonClick(const string object_name)
  {
   if(ObjectFind(g_chart_id, object_name) >= 0)
      ObjectSetInteger(g_chart_id, object_name, OBJPROP_STATE, false);

   if(object_name == UiSelectionName())
     {
      g_selection_enabled = !g_selection_enabled;
      ClearCurrentSelection();
      if(g_selection_enabled)
         SetStatus("Selection ON. Click first price.");
      else
         SetStatus("Selection OFF. Existing ranges are unchanged.");
      ChartRedraw(g_chart_id);
      return;
     }

   if(object_name == UiSections2Name() || object_name == UiSections4Name())
     {
      if(!g_selection_enabled)
        {
         SetStatus("Selection OFF. Click Enable selection first.");
         return;
        }
      if(!g_has_point_1 || !g_has_point_2)
        {
         SetStatus(StatusWithPoints("Select both prices before choosing sections."));
         return;
        }

      g_selected_sections = object_name == UiSections2Name() ? 2 : 4;
      g_state = STATE_WAITING_FOR_DIVISION;
      UpdateButtonStates();
      SetStatus(StatusWithPoints(StringFormat("%d sections selected. Press Create.",
                                               g_selected_sections)));
      return;
     }

   if(object_name == UiCreateName())
     {
      if(!g_selection_enabled)
        {
         SetStatus("Selection OFF. Click Enable selection first.");
         return;
        }
      if(!g_has_point_1 || !g_has_point_2)
        {
         SetStatus(StatusWithPoints("Select two prices before creating a range."));
         return;
        }
      if(g_selected_sections != 2 && g_selected_sections != 4)
        {
         SetStatus(StatusWithPoints("Choose 2 or 4 sections first."));
         return;
        }

      g_state = STATE_CREATING_RANGE;
      UpdateButtonStates();

      int created_range_id = -1;
      bool levels_overlap = false;
      if(!CreateRange(g_selected_sections,
                      created_range_id,
                      levels_overlap))
        {
         g_state = STATE_WAITING_FOR_DIVISION;
         UpdateButtonStates();
         SetStatus(StatusWithPoints("Range creation failed; selection retained. Retry or Cancel."));
         return;
        }

      const string overlap_note = levels_overlap
                                  ? " Some levels overlap at tick precision."
                                  : "";
      ClearCurrentSelection();
      SetStatus(StringFormat("Range %06d created.%s Click first price for the next range.",
                             created_range_id,
                             overlap_note));
      ChartRedraw(g_chart_id);
      return;
     }

   if(object_name == UiCancelName())
     {
      ClearCurrentSelection();
      SetStatus(g_selection_enabled
                ? "Selection cancelled. Click first price."
                : "Selection OFF. Click Enable selection.");
      ChartRedraw(g_chart_id);
      return;
     }

   if(object_name == UiClearName())
     {
     ClearAllRanges();
     return;
     }
  }

void HandlePanelDrag(const string object_name)
  {
   if(g_is_deinitializing)
      return;

   if(ObjectFind(g_chart_id, object_name) < 0)
      return;

   g_panel_x = (int)ObjectGetInteger(g_chart_id,
                                     object_name,
                                     OBJPROP_XDISTANCE);
   g_panel_y = (int)ObjectGetInteger(g_chart_id,
                                     object_name,
                                     OBJPROP_YDISTANCE);
   ClampPanelPosition(g_panel_x, g_panel_y);
   UpdatePanelPositions();

   ObjectSetInteger(g_chart_id,
                    UiPanelName(),
                    OBJPROP_SELECTED,
                    false);
   ObjectSetInteger(g_chart_id,
                    UiHeaderName(),
                    OBJPROP_SELECTED,
                    false);
   ChartRedraw(g_chart_id);
  }

void HandleObjectDelete(const string object_name)
  {
   if(g_is_deinitializing || g_bulk_operation)
      return;

   // Preview objects intentionally share the UI namespace, but deleting a
   // preview must not be mistaken for deleting the control panel itself.
   if(HasPrefix(object_name, PreviewPrefix()))
      return;

   if(HasPrefix(object_name, RangePrefix()))
     {
      SetStatus("One generated line was deleted; other ranges remain unchanged.");
      return;
     }

   if(HasPrefix(object_name, UiPrefix()))
     {
      CreateControlPanel();
      SetStatus(StatusWithPoints("Control panel restored."));
     }
  }

// -----------------------------------------------------------------------------
// MQL5 event handlers
// -----------------------------------------------------------------------------

int OnInit()
  {
   // MQL5 chart object names are limited to 63 characters. The longest
   // generated range name needs 23 characters after the configured prefix.
   if(StringLen(InpObjectPrefix) == 0 ||
      StringLen(InpObjectPrefix) > 40 ||
      StringFind(InpObjectPrefix, "*") >= 0)
     {
      Print("HRD: InpObjectPrefix must be 1-40 characters and must not contain '*'.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_chart_id          = ChartID();
   g_state             = STATE_SELECTION_OFF;
   g_selection_enabled = false;
   g_has_point_1       = false;
   g_has_point_2       = false;
   g_selected_sections = 0;
   g_is_deinitializing = false;
   g_bulk_operation    = false;
   InitializePanelPosition();

   long previous_delete_event_state = 0;
   if(ChartGetInteger(g_chart_id,
                     CHART_EVENT_OBJECT_DELETE,
                     0,
                     previous_delete_event_state))
      g_previous_delete_event_state = previous_delete_event_state != 0;
   else
      g_previous_delete_event_state = false;

   if(!ChartSetInteger(g_chart_id, CHART_EVENT_OBJECT_DELETE, true))
      LogLastError("could not enable object-delete notifications");

   if(!CreateControlPanel())
     {
      Print("HRD: failed to create the control panel.");
      return INIT_FAILED;
     }

   SetStatus("Selection OFF. Click Enable selection.    P1: -    P2: -");
   ChartRedraw(g_chart_id);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   g_is_deinitializing = true;

   // Permanent range lines intentionally survive indicator removal,
   // timeframe changes, and re-attachment. During a timeframe change, keep
   // the panel objects themselves so their dragged pixel position survives
   // the indicator reinitialization; transient previews are still removed.
   ResetLastError();
   if(reason == REASON_CHARTCHANGE)
      ObjectsDeleteAll(g_chart_id, PreviewPrefix());
   else
      ObjectsDeleteAll(g_chart_id, UiPrefix());
   ResetLastError();

   if(g_chart_id != 0)
      ChartSetInteger(g_chart_id,
                     CHART_EVENT_OBJECT_DELETE,
                     g_previous_delete_event_state);
   ChartRedraw(g_chart_id);
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_DRAG &&
      (sparam == UiPanelName() || sparam == UiHeaderName()))
     {
      HandlePanelDrag(sparam);
      return;
     }

   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(HasPrefix(sparam, UiPrefix()))
         HandleButtonClick(sparam);
      return;
     }

   if(id == CHARTEVENT_OBJECT_DELETE)
     {
      HandleObjectDelete(sparam);
      return;
     }

   // Handle chart price clicks last. UI events above are consumed first, and
   // HandleChartClick() independently rejects coordinates inside the panel.
   if(id == CHARTEVENT_CLICK)
     {
      HandleChartClick(lparam, (long)dparam);
      return;
     }

   if(id == CHARTEVENT_KEYDOWN && lparam == 27 && g_selection_enabled)
     {
      ClearCurrentSelection();
      SetStatus("Selection cancelled. Click first price.");
      return;
     }

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      UpdatePanelPositions();
      ChartRedraw(g_chart_id);
      return;
     }
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   return rates_total;
  }
