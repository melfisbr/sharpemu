// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using SharpEmu.Libs.Pad;

namespace SharpEmu.GUI;

/// <summary>Modal editor for the global keyboard-to-pad mapping.</summary>
public sealed class KeyboardMappingWindow : Window
{
    private readonly Dictionary<string, KeyboardPadBinding> _bindings;
    private readonly Dictionary<(string ActionId, int Slot), Button>
        _bindingButtons = new();
    private readonly TextBlock _statusText;

    private string? _capturingActionId;
    private int _capturingSlot;

    public KeyboardMappingWindow(
        IDictionary<string, KeyboardPadBinding>? bindings)
    {
        _bindings = KeyboardPadMapping.NormalizeBindings(bindings);

        Title = Localization.Instance.Get(
            "Options.KeyboardMapping.Title");
        Width = 820;
        Height = 760;
        MinWidth = 680;
        MinHeight = 520;
        CanResize = true;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var root = new Grid
        {
            Margin = new Thickness(24),
            RowDefinitions = new RowDefinitions("Auto,*,Auto"),
        };

        var header = new StackPanel
        {
            Spacing = 6,
        };
        header.Children.Add(new TextBlock
        {
            Text = Localization.Instance.Get(
                "Options.KeyboardMapping.Title"),
            FontSize = 24,
            FontWeight = Avalonia.Media.FontWeight.SemiBold,
        });
        header.Children.Add(new TextBlock
        {
            Text = Localization.Instance.Get(
                "Options.KeyboardMapping.Intro"),
            TextWrapping = Avalonia.Media.TextWrapping.Wrap,
            Opacity = 0.78,
        });
        _statusText = new TextBlock
        {
            Text = Localization.Instance.Get(
                "Options.KeyboardMapping.Hint"),
            TextWrapping = Avalonia.Media.TextWrapping.Wrap,
            Margin = new Thickness(0, 6, 0, 0),
            Opacity = 0.88,
        };
        header.Children.Add(_statusText);
        Grid.SetRow(header, 0);
        root.Children.Add(header);

        var rowsPanel = new StackPanel
        {
            Spacing = 18,
            Margin = new Thickness(0, 18, 0, 18),
        };

        foreach (var group in KeyboardPadMapping.Actions.GroupBy(
                     static action => action.GroupKey))
        {
            rowsPanel.Children.Add(BuildGroup(group.Key, group));
        }

        var scroll = new ScrollViewer
        {
            Content = rowsPanel,
            VerticalScrollBarVisibility =
                Avalonia.Controls.Primitives.ScrollBarVisibility.Auto,
        };
        Grid.SetRow(scroll, 1);
        root.Children.Add(scroll);

        var footer = new Grid
        {
            ColumnDefinitions =
                new ColumnDefinitions("Auto,*,Auto,Auto"),
        };

        var resetButton = CreateButton(
            Localization.Instance.Get(
                "Options.KeyboardMapping.Reset"),
            "ghost");
        resetButton.Click += (_, _) => ResetDefaults();
        Grid.SetColumn(resetButton, 0);
        footer.Children.Add(resetButton);

        var cancelButton = CreateButton(
            Localization.Instance.Get("Common.Cancel"),
            "ghost");
        cancelButton.Margin = new Thickness(8, 0, 0, 0);
        cancelButton.Click += (_, _) => Close(null);
        Grid.SetColumn(cancelButton, 2);
        footer.Children.Add(cancelButton);

        var saveButton = CreateButton(
            Localization.Instance.Get("Common.Save"),
            "accent");
        saveButton.Margin = new Thickness(8, 0, 0, 0);
        saveButton.Click += (_, _) =>
            Close(KeyboardPadMapping.NormalizeBindings(_bindings));
        Grid.SetColumn(saveButton, 3);
        footer.Children.Add(saveButton);

        Grid.SetRow(footer, 2);
        root.Children.Add(footer);

        Content = root;
        AddHandler(
            KeyDownEvent,
            OnPreviewKeyDown,
            RoutingStrategies.Tunnel);
    }

    private Border BuildGroup(
        string groupKey,
        IEnumerable<KeyboardPadActionDefinition> actions)
    {
        var content = new StackPanel
        {
            Spacing = 8,
        };
        content.Children.Add(new TextBlock
        {
            Text = Localization.Instance.Get(groupKey),
            FontSize = 16,
            FontWeight = Avalonia.Media.FontWeight.SemiBold,
            Margin = new Thickness(0, 0, 0, 4),
        });

        var header = new Grid
        {
            ColumnDefinitions =
                new ColumnDefinitions("2*,180,180"),
            Margin = new Thickness(4, 0, 4, 0),
        };
        var primaryHeader = new TextBlock
        {
            Text = Localization.Instance.Get(
                "Options.KeyboardMapping.Primary"),
            Opacity = 0.65,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        var secondaryHeader = new TextBlock
        {
            Text = Localization.Instance.Get(
                "Options.KeyboardMapping.Secondary"),
            Opacity = 0.65,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        Grid.SetColumn(primaryHeader, 1);
        Grid.SetColumn(secondaryHeader, 2);
        header.Children.Add(primaryHeader);
        header.Children.Add(secondaryHeader);
        content.Children.Add(header);

        foreach (var action in actions)
        {
            content.Children.Add(BuildActionRow(action));
        }

        var border = new Border();
        border.Classes.Add("card");
        border.Child = content;
        return border;
    }

    private Control BuildActionRow(
        KeyboardPadActionDefinition action)
    {
        var row = new Grid
        {
            ColumnDefinitions =
                new ColumnDefinitions("2*,180,180"),
            Margin = new Thickness(4, 2),
        };

        var label = new TextBlock
        {
            Text = Localization.Instance.Get(action.LabelKey),
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = Avalonia.Media.TextWrapping.Wrap,
        };
        Grid.SetColumn(label, 0);
        row.Children.Add(label);

        var primary = CreateBindingButton(action.Id, 1);
        var secondary = CreateBindingButton(action.Id, 2);
        primary.Margin = new Thickness(6, 0, 6, 0);
        secondary.Margin = new Thickness(6, 0, 0, 0);
        Grid.SetColumn(primary, 1);
        Grid.SetColumn(secondary, 2);
        row.Children.Add(primary);
        row.Children.Add(secondary);

        return row;
    }

    private Button CreateBindingButton(
        string actionId,
        int slot)
    {
        var button = CreateButton(
            GetBindingLabel(actionId, slot),
            "ghost");
        button.MinWidth = 150;
        button.HorizontalContentAlignment =
            HorizontalAlignment.Center;
        button.Click += (_, _) =>
            BeginCapture(actionId, slot);
        _bindingButtons[(actionId, slot)] = button;
        return button;
    }

    private static Button CreateButton(
        string content,
        string styleClass)
    {
        var button = new Button
        {
            Content = content,
            Padding = new Thickness(14, 8),
        };
        button.Classes.Add(styleClass);
        return button;
    }

    private void BeginCapture(string actionId, int slot)
    {
        CancelCaptureVisual();
        _capturingActionId = actionId;
        _capturingSlot = slot;

        if (_bindingButtons.TryGetValue(
                (actionId, slot),
                out var button))
        {
            button.Content = Localization.Instance.Get(
                "Options.KeyboardMapping.PressKey");
        }

        var action = KeyboardPadMapping.Actions.First(
            candidate =>
                string.Equals(
                    candidate.Id,
                    actionId,
                    StringComparison.OrdinalIgnoreCase));
        _statusText.Text = Localization.Instance.Format(
            "Options.KeyboardMapping.Capture",
            Localization.Instance.Get(action.LabelKey));
        Focus();
    }

    private void OnPreviewKeyDown(
        object? sender,
        KeyEventArgs args)
    {
        if (_capturingActionId is null)
        {
            if (string.Equals(
                    args.Key.ToString(),
                    "Escape",
                    StringComparison.Ordinal))
            {
                Close(null);
                args.Handled = true;
            }

            return;
        }

        var keyName = args.Key.ToString();
        if (string.Equals(
                keyName,
                "Delete",
                StringComparison.Ordinal))
        {
            AssignKey(_capturingActionId, _capturingSlot, 0);
            _statusText.Text = Localization.Instance.Get(
                "Options.KeyboardMapping.Cleared");
            CompleteCapture();
            args.Handled = true;
            return;
        }

        if (!TryMapAvaloniaKey(keyName, out var virtualKey))
        {
            _statusText.Text = Localization.Instance.Get(
                "Options.KeyboardMapping.Unsupported");
            args.Handled = true;
            return;
        }

        RemoveDuplicateAssignments(
            virtualKey,
            _capturingActionId,
            _capturingSlot);
        AssignKey(
            _capturingActionId,
            _capturingSlot,
            virtualKey);
        _statusText.Text = Localization.Instance.Format(
            "Options.KeyboardMapping.Assigned",
            KeyboardPadMapping.GetKeyDisplayName(virtualKey));
        CompleteCapture();
        args.Handled = true;
    }

    private static bool TryMapAvaloniaKey(
        string keyName,
        out int virtualKey)
    {
        virtualKey = keyName switch
        {
            "Back" => 0x08,
            "Tab" => 0x09,
            "Enter" or "Return" => 0x0D,
            "Escape" => 0x1B,
            "Left" => 0x25,
            "Up" => 0x26,
            "Right" => 0x27,
            "Down" => 0x28,
            _ => 0,
        };

        if (virtualKey != 0)
        {
            return true;
        }

        if (keyName.Length == 1 &&
            keyName[0] is >= 'A' and <= 'Z')
        {
            virtualKey = keyName[0];
            return true;
        }

        return false;
    }

    private void RemoveDuplicateAssignments(
        int virtualKey,
        string currentActionId,
        int currentSlot)
    {
        foreach (var action in KeyboardPadMapping.Actions)
        {
            var binding = _bindings[action.Id];
            if (binding.Primary == virtualKey &&
                (!string.Equals(
                     action.Id,
                     currentActionId,
                     StringComparison.OrdinalIgnoreCase) ||
                 currentSlot != 1))
            {
                binding.Primary = 0;
                RefreshBindingButton(action.Id, 1);
            }

            if (binding.Secondary == virtualKey &&
                (!string.Equals(
                     action.Id,
                     currentActionId,
                     StringComparison.OrdinalIgnoreCase) ||
                 currentSlot != 2))
            {
                binding.Secondary = 0;
                RefreshBindingButton(action.Id, 2);
            }
        }
    }

    private void AssignKey(
        string actionId,
        int slot,
        int virtualKey)
    {
        var binding = _bindings[actionId];
        if (slot == 1)
        {
            binding.Primary = virtualKey;
            if (binding.Secondary == virtualKey)
            {
                binding.Secondary = 0;
                RefreshBindingButton(actionId, 2);
            }
        }
        else
        {
            binding.Secondary = virtualKey;
            if (binding.Primary == virtualKey)
            {
                binding.Primary = 0;
                RefreshBindingButton(actionId, 1);
            }
        }

        RefreshBindingButton(actionId, slot);
    }

    private string GetBindingLabel(
        string actionId,
        int slot)
    {
        var binding = _bindings[actionId];
        var value = slot == 1
            ? binding.Primary
            : binding.Secondary;
        return KeyboardPadMapping.GetKeyDisplayName(value);
    }

    private void RefreshBindingButton(
        string actionId,
        int slot)
    {
        if (_bindingButtons.TryGetValue(
                (actionId, slot),
                out var button))
        {
            button.Content = GetBindingLabel(actionId, slot);
        }
    }

    private void ResetDefaults()
    {
        var defaults =
            KeyboardPadMapping.CreateDefaultBindings();
        foreach (var action in KeyboardPadMapping.Actions)
        {
            _bindings[action.Id] = defaults[action.Id];
            RefreshBindingButton(action.Id, 1);
            RefreshBindingButton(action.Id, 2);
        }

        CompleteCapture();
        _statusText.Text = Localization.Instance.Get(
            "Options.KeyboardMapping.ResetDone");
    }

    private void CompleteCapture()
    {
        CancelCaptureVisual();
        _capturingActionId = null;
        _capturingSlot = 0;
    }

    private void CancelCaptureVisual()
    {
        if (_capturingActionId is null)
        {
            return;
        }

        RefreshBindingButton(
            _capturingActionId,
            _capturingSlot);
    }
}
