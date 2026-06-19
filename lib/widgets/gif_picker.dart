import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../config.dart';
import '../theme.dart';

/// Pemilih GIF (Tenor). Tampilkan [GifPicker] dalam bottom sheet; mengembalikan
/// URL GIF terpilih lewat callback [onSelected].
class GifPicker extends StatefulWidget {
  final void Function(String gifUrl) onSelected;
  const GifPicker({super.key, required this.onSelected});

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
  ));
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // (previewUrl, fullUrl)
  List<(String, String)> _gifs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load([String query = '']) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = query.trim().isEmpty
          ? 'https://tenor.googleapis.com/v2/featured'
          : 'https://tenor.googleapis.com/v2/search';
      final res = await _dio.get(base, queryParameters: {
        'key': AppConfig.tenorApiKey,
        'client_key': 'wachat',
        'limit': 30,
        'media_filter': 'tinygif,gif',
        'contentfilter': 'medium',
        if (query.trim().isNotEmpty) 'q': query.trim(),
      });
      final results = (res.data is Map ? res.data['results'] : null) as List?;
      final out = <(String, String)>[];
      for (final r in results ?? const []) {
        final mf = (r as Map)['media_formats'] as Map?;
        final preview = (mf?['tinygif'] as Map?)?['url'] as String?;
        final full = (mf?['gif'] as Map?)?['url'] as String? ?? preview;
        if (preview != null && full != null) out.add((preview, full));
      }
      if (mounted) setState(() => _gifs = out);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Gagal memuat GIF. Pastikan Tenor API aktif & koneksi tersedia.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _load(q));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: false,
                  onChanged: _onQueryChanged,
                  decoration: InputDecoration(
                    hintText: 'Cari GIF di Tenor…',
                    prefixIcon: const Icon(Icons.gif_box_rounded),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: palette.muted)),
                            ),
                          )
                        : _gifs.isEmpty
                            ? Center(
                                child: Text('Tidak ada GIF',
                                    style: TextStyle(color: palette.muted)))
                            : GridView.builder(
                                padding: const EdgeInsets.all(8),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 6,
                                ),
                                itemCount: _gifs.length,
                                itemBuilder: (_, i) {
                                  final (preview, full) = _gifs[i];
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.pop(context);
                                      widget.onSelected(full);
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CachedNetworkImage(
                                        imageUrl: preview,
                                        fit: BoxFit.cover,
                                        placeholder: (_, _) => Container(
                                            color: Colors.black12),
                                        errorWidget: (_, _, _) => Container(
                                          color: Colors.black12,
                                          child: const Icon(
                                              Icons.broken_image_rounded),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
              // Atribusi Tenor (disyaratkan oleh ketentuan Tenor).
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Didukung oleh Tenor',
                    style: TextStyle(fontSize: 11, color: palette.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
