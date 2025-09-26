# Filter Rules Implementation - Debug Context

## 🎯 Current Situation

The filter rules feature has been **implemented and merged** (PR #7), but the user is experiencing **"a bunch of issues"** with the filtering functionality. We need to debug and fix these issues.

## 🔧 What Was Implemented

### Core Components
1. **FilterRule Model** (`app/models/filter_rule.rb`)
   - Pattern matching: contains, equals, regex
   - Field targeting: title, description, location  
   - Source scoping: global or source-specific rules
   - Priority ordering with position field

2. **EventFilter Service** (`app/services/calendar_hub/event_filter.rb`)
   - `should_filter?(event)` - Check if event matches any filter rules
   - `apply_filters(events)` - Apply filtering during import
   - `apply_backwards_filtering(source)` - Filter existing events
   - `apply_reverse_filtering(source)` - Re-include events

3. **FilterSyncService** (`app/services/calendar_hub/filter_sync_service.rb`)
   - Handles Apple Calendar sync integration
   - Triggers sync when filter rules change

4. **UI Components** (`app/views/filter_rules/`)
   - Management interface at `/filter_rules`
   - Form for creating/editing rules
   - Test functionality
   - Drag-and-drop reordering

5. **Integration Points**
   - Added to `CalendarHub::SyncService.upsert_events` method
   - Navigation link added to main nav
   - Controller with full CRUD operations

## 🐛 Known Issues to Investigate

### Potential Problem Areas
1. **Filter Logic Integration**
   - Check if `CalendarHub::EventFilter.apply_filters(events)` is working correctly
   - Verify `sync_exempt` flag is being set properly
   - Ensure filter rules are being applied during sync

2. **Backwards Filtering**
   - Verify backwards filtering triggers correctly when rules change
   - Check if existing events are being re-evaluated properly
   - Ensure Apple Calendar sync happens after filter changes

3. **UI/UX Issues**
   - Form validation and submission
   - Test functionality working correctly
   - Rule ordering and toggle functionality

4. **Database/Model Issues**
   - FilterRule associations with CalendarSource
   - Enum validations working properly
   - Database constraints and indexes

5. **Performance Issues**
   - Large numbers of events being processed
   - Filter rule queries efficiency
   - Sync performance impact

## 📁 Key Files to Check

### Models
- `app/models/filter_rule.rb` - Core filter rule model
- `app/models/calendar_source.rb` - Has filter_rules association
- `app/models/calendar_event.rb` - Has sync_exempt field

### Services  
- `app/services/calendar_hub/event_filter.rb` - Core filtering logic
- `app/services/calendar_hub/filter_sync_service.rb` - Apple Calendar sync
- `app/services/calendar_hub/sync_service.rb` - Integration point (line ~70)

### Controllers & Views
- `app/controllers/filter_rules_controller.rb` - CRUD operations
- `app/views/filter_rules/` - All UI components
- `config/routes.rb` - Filter rules routes

### Tests
- `test/models/filter_rule_test.rb` - Model tests
- `test/services/calendar_hub/event_filter_test.rb` - Service tests  
- `test/controllers/filter_rules_controller_test.rb` - Controller tests

## 🔍 Debugging Steps

### 1. Check Current State
```bash
# Check if filter rules exist
bin/rails console
FilterRule.count
FilterRule.active.count

# Check events with sync_exempt
CalendarEvent.where(sync_exempt: true).count
```

### 2. Test Filter Logic
```bash
# Test a specific event against filter rules
event = CalendarEvent.first
CalendarHub::EventFilter.should_filter?(event)
```

### 3. Check UI Functionality
- Navigate to `/filter_rules`
- Try creating a filter rule
- Test the rule with sample data
- Check if rules are being saved correctly

### 4. Check Sync Integration
- Create a test event that should be filtered
- Run sync and verify it's excluded from Apple Calendar
- Check sync logs for errors

## 🚨 Common Issues to Look For

1. **Missing Navigation Link** - Check if "Filters" appears in nav
2. **Route Issues** - Verify filter_rules routes are working
3. **Form Submission Errors** - Check for validation or parameter issues
4. **Filter Logic Not Applied** - Verify integration in sync service
5. **Database Migration Issues** - Ensure filter_rules table exists
6. **Association Problems** - Check CalendarSource.filter_rules relationship
7. **JavaScript Issues** - Check filter-form controller
8. **Permission Issues** - Verify filter_rule_params in controller

## 📊 Database Schema

The filter_rules table should have:
```sql
- id (primary key)
- calendar_source_id (foreign key, nullable)
- match_type (string, default: "contains")
- pattern (string, required)
- field_name (string, default: "title") 
- case_sensitive (boolean, default: false)
- active (boolean, default: true)
- position (integer, default: 0)
- created_at, updated_at
```

## 🎯 Expected Behavior

1. **Forward Filtering**: New events matching filter rules should be marked `sync_exempt: true`
2. **Backwards Filtering**: When rules change, existing events should be re-evaluated
3. **Apple Calendar Sync**: Filtered events should be excluded from sync
4. **UI Management**: Users should be able to create, edit, test, and reorder filter rules
5. **Real-time Testing**: Test form should show if sample data would be filtered

## 🔄 Recent Changes

- **PR #7 MERGED**: Complete filter rules implementation
- **PR #8 OPEN**: Character encoding fix + import start date filtering
- **Current Branch**: `fix/filter-rules-issues` (clean, ready for debugging)

## 🎯 Next Steps for LLM

1. **Reproduce the issues** - Try to identify what specific problems the user is experiencing
2. **Check each component** - Systematically verify models, services, controllers, views
3. **Test the integration** - Ensure filter rules are actually being applied during sync
4. **Fix identified issues** - Address any bugs or missing functionality
5. **Verify end-to-end** - Test complete workflow from rule creation to Apple Calendar sync

## 📝 Notes

- All tests were passing when the feature was implemented
- The implementation follows existing patterns (similar to EventMapping)
- The feature is comprehensive but may have integration or edge case issues
- User has access to `/filter_rules` UI and can see what's not working

**Branch**: `fix/filter-rules-issues` is ready for debugging work.
