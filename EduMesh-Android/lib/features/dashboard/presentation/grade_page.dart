import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/lumina_colors.dart';
import 'resource_list_page.dart';

class GradePage extends StatelessWidget {
  final String subject;

  const GradePage({
    super.key,
    required this.subject,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grades = List.generate(12, (index) => 'Grade ${index + 1}');

    return Scaffold(
      backgroundColor: cs.surface, // Automatically switches
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: cs.primary),
        title: Text(
          subject,
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w800,
            fontSize: 22.sp,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// HERO SECTION
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(22.w),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24.r),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0F766E),
                      LuminaColors.academicTeal,
                      Color(0xFF14B8A6),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: LuminaColors.academicTeal.withOpacity(0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(50.r),
                      ),
                      child: Text('SMART LEARNING',
                          style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                    ),
                    SizedBox(height: 18.h),
                    Text('$subject Learning Hub', style: TextStyle(color: Colors.white, fontSize: 25.sp, fontWeight: FontWeight.w900, height: 1.2)),
                    SizedBox(height: 10.h),
                    Text('Access textbooks, PYQs, chapter videos and learning resources organized by grade.',
                        style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 13.sp, height: 1.5)),
                    SizedBox(height: 18.h),
                    Row(
                      children: [
                        _miniStat(Icons.video_library, 'Videos'),
                        SizedBox(width: 12.w),
                        _miniStat(Icons.menu_book, 'Books'),
                        SizedBox(width: 12.w),
                        _miniStat(Icons.quiz, 'PYQs'),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 28.h),

              /// TITLE ROW
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Grade', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800, color: cs.onSurface)),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(50.r)),
                    child: Text('1 - 12', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 12.sp)),
                  ),
                ],
              ),
              SizedBox(height: 18.h),

              /// GRID
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: grades.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16.w,
                  mainAxisSpacing: 16.h,
                  childAspectRatio: 1.05,
                ),
                itemBuilder: (context, index) {
                  final grade = grades[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(22.r),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ResourcePage(subject: subject, grade: grade))),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh, // Uses theme-aware surface color
                        borderRadius: BorderRadius.circular(22.r),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(16.w),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary.withOpacity(0.1),
                            ),
                            child: Icon(Icons.school_rounded, color: cs.primary, size: 34.sp),
                          ),
                          SizedBox(height: 16.h),
                          Text(grade, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800, color: cs.onSurface)),
                        ],
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 24.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(14.r)),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 14.sp),
          SizedBox(width: 6.w),
          Text(text, style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}